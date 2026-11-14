# QRScan

QRScan 是一款 iPhone 二维码和条码扫描工具。扫到网址时，先查看域名、路径和各项查询参数，再决定是否打开。你可以复制整个链接，也可以只复制某个参数的值。

- 支持相机实时扫码和从相册选图识别。光线不足时可以打开手电筒。
- 相机扫到单个码时直接显示结果。同一画面出现多个码时，点想查看的码旁边的箭头。
- 支持简体中文和英语。识别在设备上完成，无需登录。

## 截图

| URL 预览与参数复制 | 条码结果 |
| --- | --- |
| <img src="docs/screenshots/url-result.png" width="240" alt="URL 结果页，显示域名、路径、查询参数以及复制和打开按钮"> | <img src="docs/screenshots/barcode-result.png" width="240" alt="条码结果页，显示识别出的内容和复制按钮"> |

1.0.1 适配了 iPhone Duo 的内外屏布局。以下截图来自 iPhone Duo 模拟器，用于展示内外屏布局。

| iPhone Duo 外屏 | iPhone Duo 内屏 |
| --- | --- |
| <img src="docs/screenshots/duo-outer.png" width="210" alt="iPhone Duo 模拟器外屏上的扫码首页"> | <img src="docs/screenshots/duo-inner.png" width="400" alt="iPhone Duo 模拟器内屏横向布局的扫码首页"> |

## 构建与测试

项目要求 iOS 17 或更新版本。用 Xcode 打开 `QRScan.xcodeproj`，选择 `QRScan` scheme 运行。实时相机扫描需要真机，可在模拟器中用相册选图测试识别。按 **⌘U** 运行单元测试。

## English

QRScan scans QR codes and barcodes with your iPhone camera or from a photo. A single code opens a preview. With several codes in the camera view, tap the arrow next to the one you want. Review the decoded URL and its query parameters, copy the full link or an individual value, and tap **Open Link** when you want to open it. Scanning runs on the device. The app is available in English and Simplified Chinese.

[GitHub Releases](https://github.com/longbai/qrscan/releases) · [Support](https://longbai.github.io/qrscan/) · [Privacy Policy](https://longbai.github.io/qrscan/privacy.html)
