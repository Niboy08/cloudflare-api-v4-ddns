Cloudflare API v4 Dynamic DNS Update in Bash, without unnecessary requests
Now the script also supports v6(AAAA DDNS Recoards)

----

创建 Cloudflare API 令牌，请转到 https://dash.cloudflare.com/profile/api-tokens 并按照以下步骤操作：

1. 单击创建令牌
2. 为令牌提供一个名称，例如，`cloudflare-ddns`
3. 授予令牌以下权限：
    * 区域 - 区域 - 读取
    * 区域 - 区域设置 - 读取
    * 区域 - DNS - 编辑
4. 将区域资源设置为：
    * 包括 - 特定区域 - 选择你想设置的域名

----
![image.png](https://i.loli.net/2021/11/13/OMpjhUyubrwN6Lk.png)

----
 

1
设置用于 DDNS 解析的二级域名，流量不经过CDN(云朵变灰)
添加一条A记录，例如：hkt.test.com，Proxy status设置成DNS only 


2
下载 DNNS 脚本
```
curl https://raw.githubusercontent.com/aipeach/cloudflare-api-v4-ddns/master/cf-v4-ddns.sh > /root/cf-v4-ddns.sh && chmod +x /root/cf-v4-ddns.sh
```
修改 DDNS 脚本并补充相关信息
```
vim cf-v4-ddns.sh
```
```
# incorrect api-key results in E_UNAUTH error
# 填写 Global API Key
CFKEY=

# Username, eg: user@example.com
# 填写 CloudFlare 登陆邮箱
CFUSER=

# Zone name, eg: example.com
# 填写需要用来 DDNS 的一级域名
CFZONE_NAME=

# Hostname to update, eg: homeserver.example.com
# 填写 DDNS 的二级域名(只需填写前缀)
CFRECORD_NAME=
```
设置定时任务
首次运行脚本,输出内容会显示当前IP，进入cloudflare查看 确保IP已变更为当前IP

```
./cf-v4-ddns.sh
```

定时任务

```
crontab -e
*/2 * * * * /root/cf-v4-ddns.sh >/dev/null 2>&1

# 如果需要日志，替换上一行代码
*/2 * * * * /root/cf-v4-ddns.sh >> /var/log/cf-ddns.log 2>&1
```
