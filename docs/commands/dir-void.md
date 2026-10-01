<!-- Generated from functions/dir-void.ps1. Do not edit directly. -->

# dir-void

发现并清理空文件夹或仅含单个子目录的冗余文件夹。

## 用法

```powershell
pw2401 dir-void [-Depth <int>] [-Delete <switch>] [-MoveUp <switch>]
```

## 说明

1. 发现空文件夹（无文件，无子目录）。
2. 发现冗余文件夹（无文件，仅有一个子文件夹）。
3. 使用 -Y 参数执行清理：
   - 删除空文件夹。
   - 将冗余文件夹内的唯一子文件夹上移一层。如果目标位置已存在同名目录，则在新名字后追加 .move。

## 参数

| 参数 | 类型 | 必需 | 默认值 | 说明 |
|---|---|---:|---|---|
| `-Depth` | `int` | 否 | 0 | 检查的精确目录深度。0 表示当前目录，1 表示直接子目录。 |
| `-Delete` | `switch` | 否 | — | 删除检查到的绝对空文件夹。 |
| `-MoveUp` | `switch` | 否 | — | 将冗余文件夹（仅包含单个子文件夹、无文件）内的子文件夹上移一层，并清理外层空壳。如果目标位置冲突，会加 .move 后缀。 |

## 依赖

PowerShell

## 示例

### 示例 1：delete-empty-move-up

```powershell
pw2401 dir-void -Depth 1 -Delete -MoveUp
```

清理一级子目录中的空目录，并上移冗余的单层子目录。
