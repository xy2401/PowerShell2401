<!-- Generated from functions/sys-install.ps1. Do not edit directly. -->

# sys-install

安装或卸载当前用户的 pw2401 命令路径。

## 用法

```powershell
pw2401 sys-install
```

## 说明

首次运行时创建 pw2401_home 用户环境变量并加入用户 PATH；检测到已有安装时执行卸载。
操作前会将原用户 PATH 备份到 pw2401_old_path。

## 示例

### 示例 1：toggle-install

```powershell
pw2401 install
```

安装尚未配置的 pw2401，或卸载已经配置的 pw2401。该示例会修改用户环境，因此不会自动测试。
