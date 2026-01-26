@echo off
:: 设置字符集为 UTF-8，确保中文不乱码
chcp 65001 >nul

:: 1. 自动定位到脚本所在的文件夹
cd /d "%~dp0"

:: 2. 获取并格式化当前时间 (例如: 2026-01-26_09-15-05)
set datetime=%date:~0,4%-%date:~5,2%-%date:~8,2%_%time:~0,2%-%time:~3,2%-%time:~6,2%
:: 如果小时是个位数，Windows 会在前面留空格，这里将空格替换为0
set datetime=%datetime: =0%

echo ========================================
echo [开始备份] 当前目录: %cd%
echo [提交时间] %datetime%
echo ========================================

:: 3. 执行 Git 标准三部曲
echo [1/3] 正在添加所有文件...
git add .

echo [2/3] 正在本地提交 (Commit)...
git commit -m "Auto Backup: %datetime%"

echo [3/3] 正在上传到 GitHub (Push)...
git push origin main

echo ========================================
echo 备份完成！
echo ========================================

:: 4. 保持窗口开启，直到按下回车键
pause