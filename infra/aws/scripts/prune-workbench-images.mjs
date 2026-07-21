import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const STATE_DIR = path.join(homedir(), ".local", "state", "agent-workbench");
const STATE_FILE = path.join(STATE_DIR, "ecr-images.json");

const readOption = (name) => {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] ?? "" : "";
};

const readTrackedImages = () => {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  } catch {
    return [];
  }
};

const writeTrackedImages = (images) => {
  mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
  writeFileSync(STATE_FILE, `${JSON.stringify(images, null, 2)}\n`, {
    mode: 0o600,
  });
};

const parseImageUri = (imageUri) => {
  const match = imageUri.match(
    /^\d+\.dkr\.ecr\.[^.]+\.amazonaws\.com\/([^:@]+):([^@]+)$/u,
  );

  if (!match) {
    return undefined;
  }

  return {
    imageUri,
    repositoryName: match[1],
    imageTag: match[2],
  };
};

const deleteImage = (image, region) => {
  const result = spawnSync(
    "aws",
    [
      "ecr",
      "batch-delete-image",
      "--region",
      region,
      "--repository-name",
      image.repositoryName,
      "--image-ids",
      `imageTag=${image.imageTag}`,
      "--no-cli-pager",
    ],
    { stdio: ["ignore", "ignore", "inherit"] },
  );

  return result.status === 0;
};

const region = readOption("--region");
const currentImageUri = readOption("--current");
const previousImageUri = readOption("--previous");

if (!region || !currentImageUri) {
  console.error("Image cleanup requires --region and --current.");
  process.exit(1);
}

const trackedImageUris = new Set([
  ...readTrackedImages(),
  previousImageUri,
  currentImageUri,
]);
trackedImageUris.delete("");

const retainedImageUris = [currentImageUri];

for (const imageUri of trackedImageUris) {
  if (imageUri === currentImageUri) {
    continue;
  }

  const image = parseImageUri(imageUri);
  if (image && !deleteImage(image, region)) {
    console.error(`Could not delete old workbench image ${imageUri}.`);
    retainedImageUris.push(imageUri);
  }
}

writeTrackedImages(retainedImageUris);
console.error("Workbench image retention complete: kept the deployed image.");
