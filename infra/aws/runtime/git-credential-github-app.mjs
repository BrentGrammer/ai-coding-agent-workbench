#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createSign } from "node:crypto";

const encodeBase64Url = (value) =>
  Buffer.from(value).toString("base64url");

const fetchParameter = (parameterName) =>
  execFileSync(
    "aws",
    [
      "ssm",
      "get-parameter",
      "--region",
      process.env.AWS_REGION,
      "--name",
      parameterName,
      "--with-decryption",
      "--query",
      "Parameter.Value",
      "--output",
      "text",
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
  ).trim();

const readCredentialRequest = async () => {
  let input = "";

  for await (const chunk of process.stdin) {
    input += chunk;
  }

  return Object.fromEntries(
    input
      .split(/\r?\n/u)
      .filter(Boolean)
      .map((line) => {
        const separatorIndex = line.indexOf("=");
        return [line.slice(0, separatorIndex), line.slice(separatorIndex + 1)];
      }),
  );
};

const createAppJwt = (appId, privateKey) => {
  const currentTime = Math.floor(Date.now() / 1000);
  const header = encodeBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = encodeBase64Url(
    JSON.stringify({
      iat: currentTime - 60,
      exp: currentTime + 540,
      iss: appId,
    }),
  );
  const unsignedToken = `${header}.${payload}`;
  const signer = createSign("RSA-SHA256");

  signer.update(unsignedToken);
  signer.end();

  return `${unsignedToken}.${signer.sign(privateKey, "base64url")}`;
};

const requestGitHub = async (path, appJwt, options = {}) => {
  const response = await fetch(`https://api.github.com${path}`, {
    ...options,
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${appJwt}`,
      "content-type": "application/json",
      "user-agent": "agent-workbench",
      "x-github-api-version": "2022-11-28",
      ...options.headers,
    },
  });

  if (!response.ok) {
    throw new Error(`GitHub returned ${response.status} for ${path}.`);
  }

  return response.json();
};

const issueInstallationToken = async (owner, repository, appJwt) => {
  const installation = await requestGitHub(
    `/repos/${owner}/${repository}/installation`,
    appJwt,
  );
  const tokenResponse = await requestGitHub(
    `/app/installations/${installation.id}/access_tokens`,
    appJwt,
    {
      method: "POST",
      body: JSON.stringify({ repositories: [repository] }),
    },
  );

  return tokenResponse.token;
};

const main = async () => {
  if (process.argv[2] !== "get") {
    return;
  }

  const credentialRequest = await readCredentialRequest();
  if (credentialRequest.host !== "github.com") {
    return;
  }

  const [owner, repositoryWithSuffix] = credentialRequest.path.split("/");
  const repository = repositoryWithSuffix?.replace(/\.git$/u, "");
  if (!owner || !repository) {
    throw new Error("The GitHub credential request did not include a repository.");
  }

  const appId = fetchParameter(process.env.GITHUB_APP_ID_PARAMETER_NAME);
  const privateKey = fetchParameter(
    process.env.GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME,
  );
  const appJwt = createAppJwt(appId, privateKey);
  const installationToken = await issueInstallationToken(
    owner,
    repository,
    appJwt,
  );

  process.stdout.write(`username=x-access-token\npassword=${installationToken}\n`);
};

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
