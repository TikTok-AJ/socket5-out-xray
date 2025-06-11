# 🎯 Socks5 节点一键部署脚本

这是一个全功能的 Socks5 + Xray 自动部署脚本，支持：

- ✅ 中文菜单操作（安装、重装、查看）
- ✅ 支持多节点部署，端口自动分配
- ✅ 默认账号 `wukunpeng` / 密码 `aj8888`
- ✅ 自动检测国家代码（可手动）
- ✅ 自动配置防火墙、BBR、禁用 IPv6
- ✅ 输出二维码 / 节点名称（含国家代码）
- ✅ 设置系统命令快捷名：`ja` / `AJ`
- ✅ **支持无人值守自动部署 `--auto` 模式**

---

## 🚀 使用方法

### 🔧 手动菜单模式（推荐首次使用）

```bash
bash -c 'curl -sSL https://raw.githubusercontent.com/TikTok-AJ/socket5-out-xray/main/AJ.sh -o /usr/local/bin/aj && chmod +x /usr/local/bin/aj && ln -sf /usr/local/bin/aj /usr/local/bin/AJ && /usr/local/bin/aj'
```

运行后会出现中文菜单，可选择安装/重装/查看节点等操作。

---

### 🤖 自动模式（无人值守，适合脚本化）

```bash
bash -c 'curl -sSL https://raw.githubusercontent.com/TikTok-AJ/socket5-out-xray/main/AJ.sh -o /usr/local/bin/aj && chmod +x /usr/local/bin/aj && ln -sf /usr/local/bin/aj /usr/local/bin/AJ && /usr/local/bin/aj --auto'
```

自动完成以下内容：

- 检测国家代码
- 安装 1 个 Socks5 节点
- 自动配置系统
- 输出节点二维码
- 设置 `ja` / `AJ` 命令别名以便下次运行

---

## 📦 脚本运行后可使用命令

- `ja` 或 `AJ`：再次运行脚本菜单
- 节点端口从 `20000~65000` 随机生成
- 日志自动每周清理一次

---

## 📄 示例截图

> 安装完成后节点信息示意（含二维码）：

```
🔗 连接地址: socks://root:aj8888@123.123.123.123:10808#SOCKS5-US-10808
📎 终端二维码:
█████████████████████████
██ ▄▄▄▄▄ ██▄▀▄█  ▄▄▄▄▄ ██
██ █   █ █▀ ▀▄█ █   █ ██
██ █▄▄▄█ █▀█ █▄ █▄▄▄█ ██
██▄▄▄▄▄█ █ ▀ ▄█▄▄▄▄▄█ ██
█████████████████████████
```

---

## 💡 注意事项

- 默认用户名为：`wukunpeng`，密码为：`aj8888`
- 每次运行都自动设置快捷命令 `ja` 和 `AJ`
- 支持所有主流国家（US / UK / DE / JP / FR ...）
