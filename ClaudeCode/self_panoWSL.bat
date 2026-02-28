@echo off
:: start 后面第一个双引号里的内容就是窗口标题
:: --cd 参数直接指定 WSL 启动目录，完美避开引号嵌套报错
start "Self_Panel" wsl --cd "/mnt/d/Projects_New/Side - SelfPanorama" -e bash