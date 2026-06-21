# Folder Encryption

一个使用 7-Zip 对文件夹进行加密和解密的 Windows 批处理脚本。

```text
Author: River Du
Date: 2024-06-22
Repository: https://github.com/River-Du/folder-encryption
```

## 简介

Folder Encryption 是一个轻量级 Windows BAT 脚本，用于将指定文件夹加密压缩为带密码保护的 `.7z` 文件，也可以将同名 `.7z` 压缩包解密解压回文件夹。

脚本适合个人本地使用。只需要在脚本顶部配置目标文件夹名称，然后双击运行 `encryption_decryption.bat` 即可。

## 仓库内容

```text
folder-encryption/
├─ 7za.exe
└─encryption_decryption.bat
```

其中：

* `encryption_decryption.bat`：加密 / 解密脚本
* `7za.exe`：7-Zip 命令行程序，可用于免安装运行

## 功能

* 将文件夹加密压缩为 `.7z` 文件
* 将 `.7z` 压缩包解密解压为文件夹
* 支持同时配置多个目标文件夹
* 自动判断当前应执行加密或解密
* 输入密码时不会显示明文
* 自动使用同级目录中的 `7za.exe`

## 运行要求

* Windows
* PowerShell

本仓库已包含 `7za.exe`，通常不需要额外安装 7-Zip。

如果你删除了仓库中的 `7za.exe`，也可以自行安装 7-Zip，或将 `7z.exe` / `7za.exe` 放到 BAT 脚本同级目录中。

## 使用方法

### 1. 用记事本打开脚本

右键点击 `encryption_decryption.bat`，选择在记事本中编辑。

如果编辑器需要选择编码方式，请选择 GBK 或 ANSI 编码格式。

不要直接双击打开进行编辑，因为双击会运行脚本。

### 2. 修改目标文件夹

在脚本顶部找到这一行：

```bat
set TARGETS="private_1" "private_2" "private_3" "private_4"
```

把里面的文件夹名称改成你想加密 / 解密的文件夹名称。

例如：

```bat
set TARGETS="my_private_folder"
```

### 3. 保存并运行

修改完成后，在记事本中保存文件。

然后双击运行：

```text
encryption_decryption.bat
```

如果目标文件夹存在，脚本会将其加密压缩。

如果同名 `.7z` 压缩包存在，脚本会将其解密解压。

示例：

```text
private_1    -> private_1.7z
private_1.7z -> private_1
```

## 配置项

加密成功后是否删除原文件夹：

```bat
set "DELETE_SOURCE_AFTER_ENCRYPT=1"
```

解密成功后是否删除原压缩包：

```bat
set "DELETE_ARCHIVE_AFTER_DECRYPT=1"
```

手动指定 7-Zip 程序路径，留空则自动查找：

```bat
set "SEVENZIP_EXE="
```

## 注意事项

* 请牢记密码，脚本无法恢复遗忘的密码。
* 建议先使用测试文件夹验证脚本流程。
* 重要文件请保留额外备份。
* 本脚本适合个人本地使用，不适合作为企业级安全管理方案。
* 如果你分发或修改 `7za.exe`，请注意遵守 7-Zip 相关许可证要求。
