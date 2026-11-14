# QRScan

QRScan is an iPhone app for scanning QR codes and barcodes with the camera or from a photo. When a code contains a URL, you can inspect its domain, path, and query parameters, then copy the full link, copy an individual parameter value, or tap **Open Link**.

- A single code in the camera view opens its result automatically. When several codes are visible, tap the arrow beside the one you want.
- Use the flashlight in low light, or choose a saved image from Photos.
- Recognition runs on the device. QRScan requires no account and is available in English and Simplified Chinese.

## Screenshots

| URL details and parameter copying | Barcode result |
| --- | --- |
| <img src="docs/screenshots/url-result.png" width="240" alt="URL result with its domain, path, query parameters, and buttons to copy or open the link"> | <img src="docs/screenshots/barcode-result.png" width="240" alt="Barcode result with its decoded content and a copy button"> |

Version 1.0.1 adapts the layout to the iPhone Duo outer and inner displays. The screenshots below were captured in the iPhone Duo simulator.

| iPhone Duo outer display | iPhone Duo inner display |
| --- | --- |
| <img src="docs/screenshots/duo-outer.png" width="210" alt="QRScan on the iPhone Duo simulator outer display"> | <img src="docs/screenshots/duo-inner.png" width="400" alt="QRScan in landscape on the iPhone Duo simulator inner display"> |

## Build and test

QRScan requires iOS 17 or later. Open `QRScan.xcodeproj` in Xcode and run the `QRScan` scheme. Use a physical iPhone to test live scanning, or choose a photo in the simulator to test image recognition. Press **⌘U** to run the unit tests.

[GitHub Releases](https://github.com/longbai/qrscan/releases) · [Support](https://longbai.github.io/qrscan/) · [Privacy Policy](https://longbai.github.io/qrscan/privacy.html)
