# Security and privacy

## Reporting

Do not open a public issue for a vulnerability, exposed credential, identifiable traffic evidence or privacy incident. Contact the repository owner privately through the security-reporting method configured on the GitHub repository.

Include only the minimum information needed to reproduce the problem. Remove access tokens, faces, licence plates, precise locations and private video.

## Sensitive material

The following must never be committed:

- `backend/.env` and cloud credentials;
- Azure access tokens and subscription secrets;
- uploaded videos and generated evidence;
- faces, licence plates and owner/registry data;
- downloaded ONNX model binaries;
- Android signing keys and `local.properties`.

## Deployment baseline

- Use HTTPS and authenticated APIs.
- Use Microsoft Entra managed identities and Key Vault instead of embedded keys.
- Store evidence in private containers with least-privilege access.
- Encrypt data in transit and at rest.
- Apply retention and deletion policies.
- Record operator decisions and access events.
- Keep automatic enforcement disabled.
- Complete a legal, privacy and model-risk review before processing public-road footage.
