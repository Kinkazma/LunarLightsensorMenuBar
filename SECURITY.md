# Security Policy

## Overview
LunarSensorMenuBar is an open source macOS utility that forwards ambient light readings from a SmartThings sensor to Lunar Pro. The application stores OAuth credentials locally so it can refresh the access token and serve readings over a small HTTP server. This document describes how data is handled and how to report security problems.

## Data Handling
- The SmartThings client ID, client secret, refresh token, device ID, TV name and other settings are persisted in `UserDefaults` in plain text. They are not encrypted.
- Placeholder tokens defined in `Constants.swift` become part of the compiled binary if not replaced before building.
- Access tokens obtained from the SmartThings API are also saved in `UserDefaults` and renewed automatically using the stored refresh token.
- A log file named `LunarSensorApp.log` is recreated in `~/Library/Logs` on each launch. The log contains diagnostic messages but excludes tokens and secrets.

## Network
- The app runs an HTTP server via Swifter on port `10001`. No TLS or authentication is used. While the README indicates the service listens on `127.0.0.1`, the current implementation does not explicitly bind to the loopback address and may expose the port on the local network depending on the environment.
- Endpoints `/sensor/ambient_light` and `/events` provide plain JSON or Server‑Sent Events containing the latest lux values for Lunar.

## Supported Versions
This project is delivered **as is** with no guarantee of updates, bug fixes or security patches. Use the latest commit from this repository if you wish to track changes.

## Reporting Security Issues
If you believe you have found a vulnerability, please open a GitHub issue. There is no formal response schedule, but issues will be reviewed when possible. Include as much detail as you can so the problem can be reproduced.
