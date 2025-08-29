import sys
import os
import openai
from google import genai
import yaml, argparse, json
import prompts
import re

debug = False

#REGEX for ABORT pattern
ABORT_PATTERN = re.compile(r'ABORT:\s*(.*)')

def load_knowledge_hub(query):
    # 根據任務加載相關的知識庫文件
    # 返回格式化的字符串
    pass

def generate_ai_response(prompt):
    if debug:
        print("=== Prompt ===")
        print(prompt)
        print("=== End Prompt ===")
    
    response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt
            )

    if debug:
        print("=== Response ===")
        print(response.text)
        print("=== End Response ===")

    # Check for ABORT pattern in response
    match = ABORT_PATTERN.search(response.text)
    if match:
        reason = match.group(1).strip()
        print(f"Process aborted by AI: {reason}")
        sys.exit(1)

    return response.text

def get_json_arg_from_pr_body(pr_body):
    prompt = f"""
    You are given the following PR body:
    {pr_body}
    Try to extract relevant arguments named explicitly in the body:
    Arguments include:
    - "additional_context", "spec_summary", "arch_content", "refine_feedback"
    It should be specified in a line like this:
    - "additional_context: <value>"
    Format the output as a JSON dictionary.
    """
    response = generate_ai_response(prompt)
    try:
        json_dict = json.loads(response)
    except json.JSONDecodeError:
        json_dict = {}
    return json_dict

def write_to_files(response, task):
    """
    只寫入 FILE: ... 到 END FILE 之間的內容，其他行全部忽略。
    """
    current_file = None
    f = None
    writing = False
    for line in response.splitlines():
        if line.startswith("FILE:"):
            current_file = line[len("FILE:"):].strip()
            f = open(current_file, "w")
            writing = True
        elif line.startswith("END FILE"):
            if f:
                f.close()
                f = None
            current_file = None
            writing = False
        elif writing and f:
            f.write(line + "\n")
        # 其他情況（未進入 FILE: 區塊）全部忽略
        # 例如：調試用的 print 輸出

def main(task, pr_title, pr_body, refine=False, knowledge_query=None, json_args=None):
    json_dict = {}
    if json_args:
        #json args is string list, convert to dict
        json_dict = json.loads(json_args)
    else:
        json_dict = get_json_arg_from_pr_body(pr_body)
    additional_context = json_dict.get("additional_context", "")
    spec_summary = json_dict.get("spec_summary", "")
    arch_content = json_dict.get("arch_content", "")
    refine_feedback = json_dict.get("refine_feedback", "")
    if refine:
        #read feedback from file and original content from file
        with open(refine_feedback, "r") as f:
            feedback_content = f.read()
        #original filename is just refine_feedback without .feedback
        original_filename = refine_feedback.replace(".feedback", "")
        with open(original_filename, "r") as f:
            original_content = f.read()
    
    # 1. 加載任務相關的知識
    knowledge = load_knowledge_hub(knowledge_query)
    
    # 2. 構建提示詞
    pre_prompt = f"""
    PR Title: {pr_title}
    PR Body: {pr_body}
    Knowledge Base:
    {knowledge}
    """

    # 2.1
    print("Task:", task)
    if task == "spec-analysis":
        prompt = prompts.get_spec_analyst_prompt(additional_context) + pre_prompt
    elif task == "architecture":
        prompt = prompts.get_architect_prompt(spec_summary) + pre_prompt
    elif task == "coding":
        prompt = prompts.get_coder_prompt(arch_content) + pre_prompt
    elif refine:
        prompt = prompts.get_refinement_prompt(original_content,feedback_content,original_filename) + pre_prompt
    else:
        raise ValueError("Unknown task: " + task)

    # 3. 獲取 AI 響應
    print("Generating AI response...")
    response = generate_ai_response(prompt)
    
    # 4. 將響應寫入適當的文件
    print("Writing to files...")
    write_to_files(response, task)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--step", required=True, help="The development step to run (e.g., spec_analysis, architecture, coding)")
    parser.add_argument("--pr-title", required=True, help="Title for the pull request")
    parser.add_argument("--pr-body", required=True, help="Body for the pull request")
    parser.add_argument("--refine", action="store_true", help="Whether to refine the output")
    parser.add_argument("--json_args", help="Additional JSON arguments for the step")
    parser.add_argument("--debug", action="store_true", help="Enable debug mode")
    args = parser.parse_args()

    debug = args.debug

    client = genai.Client(api_key=os.getenv("GOOGLE_GENAI_KEY"))

    main(args.step, args.pr_title, args.pr_body, args.refine, json_args=args.json_args if args.json_args else None)

    print(f"Step '{args.step}' completed.")