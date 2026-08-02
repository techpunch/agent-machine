---
name: docker-account
summary: A Docker account, and a personal access token for it
when: before-you-start
---
About two minutes, on your laptop rather than the server.

1. Sign in or sign up at https://app.docker.com — the free tier is enough.
2. Settings, then Personal access tokens, then Generate. Read scope is sufficient: `sbx` only needs
   to authenticate, not publish anything.
3. Copy the token, and note your Docker username — you need both.

Why a token rather than the normal sign-in: `sbx login` opens a browser by default, and a headless
server has none. The token form works over SSH with nobody at the screen.

Both go in the macOS Keychain when I ask, so they never land in this repo or in `server.env`.
