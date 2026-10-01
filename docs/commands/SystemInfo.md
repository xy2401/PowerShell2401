<!-- Generated from functions/SystemInfo.ps1. Do not edit directly. -->

# SystemInfo

显示 Windows 操作系统、处理器和内存信息。

## 用法

```powershell
pw2401 SystemInfo
```

## 说明

通过 CIM 查询当前 Windows 系统的版本、CPU 名称及物理内存总量，并输出格式化快照。

## 依赖

PowerShell

## 示例

### 示例 1：system-summary

```powershell
pw2401 SystemInfo
```

显示当前计算机的系统信息。
