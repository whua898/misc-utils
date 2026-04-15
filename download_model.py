"""
手动下载模型脚本
使用 HuggingFace Hub API 下载模型文件
"""

import os
from huggingface_hub import snapshot_download

# 设置国内镜像
os.environ['HF_ENDPOINT'] = 'https://hf-mirror.com'

print("=" * 60)
print("Unsloth 模型下载工具")
print("=" * 60)
print(f"\n镜像地址: {os.environ['HF_ENDPOINT']}")
print("\n可用模型 (适合 GTX 1660 6GB):")
print("\n【超轻量级 - 快速测试】")
print("1. Qwen2.5-0.5B-Instruct (~538MB) - 最快，适合测试")
print("2. Gemma-2-2b-it (~1.7GB) - Google出品，性能优秀")
print("\n【轻量级 - 日常使用】")
print("3. Llama-3.2-1B-Instruct (~1.1GB) - Meta官方，平衡性好")
print("4. Qwen2.5-1.5B-Instruct (~3GB) - 中文能力强")
print("5. Gemma-2-2b-PTE (uncensored) (~1.7GB) - 无限制版本")
print("\n【中等级别 - 需要调整参数】")
print("6. Llama-3.1-8B-Instruct (~4.5GB, 4-bit) - 强大但显存紧张")
print("7. Qwen2.5-7B-Instruct (~4.2GB, 4-bit) - 中文优化")
print("\n【GGUF格式 - llama.cpp推理】")
print("8. Gemma-4-31B-CRACK-GGUF (~17GB) - Crack版，需手动下载")

choice = input("\n请选择模型 (1-8, 默认1): ").strip() or "1"

models = {
    "1": "unsloth/Qwen2.5-0.5B-Instruct",
    "2": "unsloth/gemma-2-2b-it",
    "3": "unsloth/Llama-3.2-1B-Instruct",
    "4": "unsloth/Qwen2.5-1.5B-Instruct",
    "5": "unsloth/gemma-2-2b",  # PTE/uncensored基础版
    "6": "unsloth/Llama-3.1-8B-Instruct",
    "7": "unsloth/Qwen2.5-7B-Instruct",
    "8": None  # GGUF Crack版，需要手动下载
}

model_name = models.get(choice, models["1"])
print(f"\n开始下载: {model_name}")

if choice == "8":
    print("\n" + "=" * 60)
    print("GGUF Crack版需要手动下载")
    print("=" * 60)
    print("\n推荐下载源：")
    print("1. 直接在 HuggingFace 搜索: Gemma-4-31B-JANG_4M-CRACK-GGUF")
    print("2. 使用 Civitai: https://civitai.com/models/gemma-4-crack")
    print("3. 使用国内镜像站下载")
    print("\n下载后保存位置：")
    print("  D:\Users\wh898\models\gemma-4-31b-crack.gguf")
    print("\n使用方法：")
    print("  - 安装 llama-cpp-python: pip install llama-cpp-python")
    print("  - 或使用 WebUI: 1webui, KoboldCPP, Oobabooga")
    print("\n注意: 该模型约 17GB，需要较大内存和显存")
    print("=" * 60)
    exit(0)
else:
    print("注意: 8B模型在6GB显存上需要使用4-bit量化和较小的batch size")
    
print("这可能需要几分钟到几十分钟，取决于网络速度...\n")

try:
    # 下载模型
    model_path = snapshot_download(
        repo_id=model_name,
        cache_dir="C:\\Users\\wh898\\.cache\\huggingface\\hub",
        resume_download=True,  # 支持断点续传
    )
    
    print("\n" + "=" * 60)
    print("✓ 下载完成！")
    print("=" * 60)
    print(f"模型保存在: {model_path}")
    print("\n现在可以运行 test_unsloth.py 测试了！")
    
except Exception as e:
    print(f"\n✗ 下载失败: {e}")
    print("\n建议:")
    print("1. 检查网络连接")
    print("2. 使用 IDM 手动下载（见 README）")
    print("3. 稍后重试")
