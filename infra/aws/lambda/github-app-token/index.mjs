import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";
import { createSign } from "node:crypto";

const ssmClient = new SSMClient({});

const GITHUB_NAME_PATTERN = /^[A-Za-z0-9_.-]+$/u;

const allowedRepositories = (process.env.ALLOWED_REPOSITORIES ?? "")
  .split(",")
  .map((entry) => entry.trim())
  .filter(Boolean);

const encodeBase64Url = (value) => Buffer.from(value).toString("base64url");

const readParameter = async (parameterName) => {
  const result = await ssmClient.send(
    new GetParameterCommand({ Name: parameterName, WithDecryption: true }),
  );
  const value = result.Parameter?.Value;

  if (!value) {
    throw new Error(`The parameter ${parameterName} is empty.`);
  }

  return value;
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

const checkRepositoryIsAllowed = (owner, repository) => {
  if (
    !GITHUB_NAME_PATTERN.test(owner ?? "") ||
    !GITHUB_NAME_PATTERN.test(repository ?? "")
  ) {
    throw new Error("Give an owner and a repository as plain GitHub names.");
  }

  if (
    allowedRepositories.length > 0 &&
    !allowedRepositories.includes(`${owner}/${repository}`)
  ) {
    throw new Error(
      `This workbench cannot make tokens for ${owner}/${repository}.`,
    );
  }
};

// Returns only a short-lived installation token. The App private key stays in
// this function and never goes back to the caller.
export const handler = async (event) => {
  const owner = event?.owner;
  const repository = event?.repository;

  checkRepositoryIsAllowed(owner, repository);

  const [appId, privateKey] = await Promise.all([
    readParameter(process.env.GITHUB_APP_ID_PARAMETER_NAME),
    readParameter(process.env.GITHUB_APP_PRIVATE_KEY_PARAMETER_NAME),
  ]);

  const appJwt = createAppJwt(appId, privateKey);
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

  return { token: tokenResponse.token, expiresAt: tokenResponse.expires_at };
};
