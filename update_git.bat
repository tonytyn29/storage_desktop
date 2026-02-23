@echo off
:: 设置字符集为 UTF-8，确保中文不乱码
chcp 65001 >nul

:: 1. 定位到脚本所在文件夹
cd /d "%~dp0"

:: 2. 设置大文件阈值 (单位: 字节)
:: 50MB = 50 * 1024 * 1024 = 52428800 字节
set /a max_size=52428800

:: 3. 获取并格式化当前时间 (2026-01-26_09-15-05)
set datetime=%date:~0,4%-%date:~5,2%-%date:~8,2%_%time:~0,2%-%time:~3,2%-%time:~6,2%
set datetime=%datetime: =0%

echo ========================================
echo [开始备份] 目录: %cd%
echo [大文件限制] %max_size% 字节 (约50MB)
echo ========================================

:: 4. 动态扫描大文件并加入 .gitignore
echo [工具] 正在扫描超大文件...

:: 创建空的 .gitignore 如果它不存在
if not exist .gitignore type nul > .gitignore

:: 遍历当前文件夹及子文件夹下所有文件
for /r %%i in (*) do (
    :: 排除 .git 文件夹内的内容和 .gitignore 自身
    echo %%i | findstr /i "\.git\\" >nul
    if errorlevel 1 (
        if not "%%~nxi"==".gitignore" (
            :: 比较文件大小
            if %%~zi GTR %max_size% (
                :: 检查是否已经在 .gitignore 中，不在则添加
                findstr /x /c:"%%~nxi" .gitignore >nul 2>&1
                if errorlevel 1 (
                    echo %%~nxi>>.gitignore
                    echo [忽略] 已拉黑大文件: %%~nxi (大小: %%~zi 字节)
                )
            )
        )
    )
)

:: 5. 执行 Git 标准三部曲
echo.
echo [1/3] 正在添加文件 (已自动跳过大文件)...
git add .

echo [2/3] 正在本地提交 (Commit)...
git commit -m "Auto Backup: %datetime%"

echo [3/3] 正在上传到 GitHub (Push)...
git push origin main

echo ========================================
echo 备份完成！
echo ========================================

:: 6. 保持窗口开启
pause