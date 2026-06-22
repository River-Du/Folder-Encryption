# Folder Encryption

一个使用 7-Zip 对文件夹进行加密和解密的 Windows 批处理脚本。

```text
Author: River Du
Date: 2024-06-22
Repository: https://github.com/River-Du/folder-encryption
```

## 简介

Folder Encryption 是一个轻量级 Windows BAT 脚本，可将指定文件夹加密压缩为带密码保护的 `.7z` 文件，也可将同名 `.7z` 压缩包解密还原为文件夹。

适合个人本地使用。编辑脚本顶部的目标文件夹配置后，双击运行即可。

## 仓库内容

```text
folder-encryption/
├─ 7za.exe
├─ encryption_decryption.bat
├─ encryption_decryption_ascii.bat
└─ README.md
```

* `encryption_decryption.bat`：中文显示版本，推荐优先使用。
* `encryption_decryption_ascii.bat`：英文兼容版本，适合部分 Win10 中文 BAT 运行异常、乱码或黑框一闪而过的情况。
* `7za.exe`：7-Zip 命令行程序，供脚本调用，不是程序入口。

普通用户应双击运行 `.bat` 脚本，而不是直接运行 `7za.exe`。

## 功能

* 文件夹加密压缩为 `.7z`
* `.7z` 压缩包解密还原为文件夹
* 支持多个目标文件夹
* 自动判断加密或解密
* 密码输入时不显示明文
* 免安装使用同级目录中的 `7za.exe`
* 先生成临时结果，再替换正式文件，降低误删和半成品风险

## 运行要求

* Windows
* PowerShell

仓库已包含 `7za.exe`，通常不需要额外安装 7-Zip。

## 使用方法

### 1. 编辑脚本

右键点击脚本，选择用记事本或其他纯文本编辑器打开。

推荐优先编辑：

```text
encryption_decryption.bat
```

如果中文版本运行异常，再改用：

```text
encryption_decryption_ascii.bat
```

不要直接双击脚本进行编辑，因为双击会运行脚本。

### 2. 修改目标文件夹

在脚本顶部找到：

```bat
set TARGETS="private_1" "private_2" "private_3" "private_4"
```

改成你想加密 / 解密的文件夹名称，例如：

```bat
set TARGETS="my_private_folder"
```

### 3. 保存并运行

保存后，双击运行对应的 `.bat` 文件。

如果目标文件夹存在，脚本会加密生成同名 `.7z` 压缩包：

```text
private_1 -> private_1.7z
```

如果同名 `.7z` 压缩包存在，脚本会解密还原为文件夹：

```text
private_1.7z -> private_1
```

如果同时存在可加密和可解密目标，脚本会提示选择本轮整体模式。

## 版本选择

一般使用：

```text
encryption_decryption.bat
```

如果遇到中文乱码、黑框一闪而过、Win10 运行异常等问题，使用：

```text
encryption_decryption_ascii.bat
```

两个版本功能相同，仅显示语言和兼容性处理不同。

## 注意事项

* 请牢记密码，脚本无法恢复遗忘的密码。
* 重要文件请保留额外备份。
* 建议先用测试文件夹验证流程。
* 不建议把磁盘根目录作为目标。
* 处理过程中不要手动移动、删除或占用相关文件。
* 本脚本适合个人本地使用，不适合作为企业级安全管理方案。
* 分发或修改 `7za.exe` 时，请遵守 7-Zip 相关许可证要求。
