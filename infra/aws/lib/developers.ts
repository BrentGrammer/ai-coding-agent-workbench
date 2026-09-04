const DEVELOPER_NAME = /^[a-z][a-z0-9-]{0,31}$/;

export const SHARED_STACK_ID = "AwsNativeWorkbenchSharedStack";

export function parseDevelopers(
  raw: unknown,
  fallbackUsername: string,
): string[] {
  const unique = [...new Set(developerNames(raw, fallbackUsername))];
  if (unique.length === 0) {
    throw new Error(
      "Set CDK context developers to a comma-separated list of names, for example -c developers=alice,bob",
    );
  }
  return unique;
}

export function normalizeDeveloperName(name: string): string {
  const normalized = name.trim().toLowerCase();
  if (!DEVELOPER_NAME.test(normalized)) {
    throw new Error(
      `Invalid developer name "${name}". Use a lowercase letter followed by up to 31 letters, digits, or hyphens.`,
    );
  }
  return normalized;
}

export function ec2StackId(developer: string): string {
  return `AwsNativeWorkbenchEc2Stack-${developer}`;
}

export function ec2InstanceName(developer: string): string {
  return `aws-native-agent-workbench-ec2-${developer}`;
}

export function sshPublicKeyFor(
  context: { tryGetContext(key: string): unknown },
  developer: string,
  developerCount: number,
): string | undefined {
  const named = readPublicKey(context.tryGetContext(`sshPublicKey-${developer}`));
  if (named) {
    return named;
  }
  if (developerCount === 1) {
    return readPublicKey(context.tryGetContext("sshPublicKey"));
  }
  return undefined;
}

function developerNames(raw: unknown, fallbackUsername: string): string[] {
  if (Array.isArray(raw)) {
    return raw.map((value) => normalizeDeveloperName(String(value)));
  }
  if (typeof raw === "string" && raw.trim() !== "") {
    return raw.split(",").map((value) => normalizeDeveloperName(value));
  }
  if (raw !== undefined && raw !== null) {
    throw new Error(
      "developers must be a comma-separated string or an array of names",
    );
  }
  return [normalizeDeveloperName(fallbackUsername)];
}

function readPublicKey(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const key = value.trim();
  return key === "" ? undefined : key;
}
