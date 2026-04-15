""" 
Unsloth 快速入门测试脚本
演示如何加载模型并进行推理

支持的模型：
- unsloth/Qwen2.5-0.5B-Instruct (538MB, 适合测试)
- unsloth/gemma-2-2b-it (1.7GB)
- unsloth/Llama-3.2-1B-Instruct (1.1GB)

注意：需要先使用 download_model.py 下载模型
"""

from unsloth import FastLanguageModel
import torch

def test_unsloth():
    print("=" * 60)
    print("Unsloth 快速测试")
    print("=" * 60)
    
    # 1. 检查 CUDA 可用性
    print("\n1. 检查 GPU...")
    print(f"   CUDA 可用: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"   GPU: {torch.cuda.get_device_name(0)}")
        print(f"   显存: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.2f} GB")
    
    # 2. 加载模型（使用一个小模型进行快速测试）
    print("\n2. 加载模型...")
    print("   模型: unsloth/Qwen2.5-0.5B-Instruct (更小，下载更快)")
    print("   这可能需要几分钟时间，取决于网络速度...\n")
    
    try:
        model, tokenizer = FastLanguageModel.from_pretrained(
            model_name="unsloth/Qwen2.5-0.5B-Instruct",  # 使用更小的模型
            max_seq_length=2048,
            dtype=None,  # 自动选择
            load_in_4bit=True,  # 使用 4-bit 量化节省显存
        )
        
        print("   ✓ 模型加载成功！")
        
        # 3. 启用推理优化
        FastLanguageModel.for_inference(model)
        print("   ✓ 推理优化已启用")
        
        # 4. 准备输入
        print("\n3. 测试推理...")
        messages = [
            {"role": "user", "content": "请简单介绍一下什么是人工智能？"}
        ]
        
        # 应用聊天模板
        input_text = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True
        )
        
        # 编码输入
        inputs = tokenizer(
            [input_text],
            return_tensors="pt"
        ).to("cuda")
        
        # 5. 生成回答
        print("   正在生成回答...\n")
        outputs = model.generate(
            **inputs,
            max_new_tokens=256,
            use_cache=True,
            temperature=0.7,
            top_p=0.9,
        )
        
        # 解码输出
        response = tokenizer.batch_decode(outputs, skip_special_tokens=True)[0]
        
        # 提取助手的回答
        assistant_response = response.split("assistant\n")[-1].strip()
        
        print("-" * 60)
        print("问题:", messages[0]["content"])
        print("-" * 60)
        print("回答:")
        print(assistant_response)
        print("-" * 60)
        
        print("\n✓ 测试完成！Unsloth 工作正常！")
        
        return True
        
    except Exception as e:
        print(f"\n✗ 错误: {e}")
        print("\n提示:")
        print("  - 确保网络连接正常（需要下载模型）")
        print("  - 首次运行会下载模型文件（约 2-3 GB）")
        print("  - 如果显存不足，可以尝试更小的模型")
        return False

if __name__ == "__main__":
    test_unsloth()
