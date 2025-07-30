# LunarSensorMenuBar

A macOS menu bar utility that forwards ambient light data from a SmartThings sensor to Lunar Pro. When a specified television is detected, the app polls SmartThings for illuminance readings and exposes them over a local HTTP server so Lunar can synchronize your display brightness.

## Features
- Detects a configured external display and switches Lunar between the Mac's own ambient light sensor and SmartThings.
- Runs a small HTTP server on `127.0.0.1:10001` with `/sensor/ambient_light` and `/events` endpoints.
- Adjustable polling interval and optional smoothing of brightness transitions.
- Menu shows "TV name : connecté" or "TV name : non connecté" below the current brightness.

## Requirements
- macOS with Xcode.
- [Lunar](https://lunar.fyi/) configured to read from an HTTP sensor.
- SmartThings account and OAuth credentials.

## Setup
1. Unzip `LunarSensorAppMenuBar.xcodeproj.zip` and open the project in Xcode.
2. Build and run the application.
3. Use the menu bar item **Renseignez vos données** to enter your SmartThings information (TV Name, Client ID, Client Secret, Refresh Token, Device ID and Redirect URI).
4. If needed, adjust OAuth scopes in `Constants.swift`.

## Usage
The status bar icon displays `ALS Mac` when using the Mac's sensor or `TV Name` when the SmartThings sensor is active. Use the menu to tweak polling intervals and enable smoothing.

## Plus d'infos.
See [DetailledReadme.md](DetailledReadme.md) to have a very detailed explanation of the installation procedure and application capacity.
For more visual comfort once downloaded, check out: [DetailledReadme.rtf](DetailledReadme.rtf)

## Security
See [SECURITY.md](SECURITY.md) for supported versions and reporting guidelines.

## License
Licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
