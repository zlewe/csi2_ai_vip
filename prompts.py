# Contains all the prompts for the agents, determined by the role/label

def get_master_prompt():
  return """
  [MASTER COMMAND: IF THERE IS ANY ISSUE WITH GENERATING A RESPONSE, EITHER SYNTAX OR CONTENT, OR YOU SIMPLY CANNOT DO IT, OUTPUT "ABORT: <REASON>".]

  You are in a team of expert agents working together to build UVM VIP for a given
  protocol specification. 
  """

def file_output_instructions():
  return """
    File Output Instructions:
    - The are two directories: docs and uvm. 
      - All uvm code should go to uvm directory, don't create extra child dir (depth=1).
      - spec summary markdown files go to docs/spec_summary.md. 
      - Detail spec analysis markdown files go to docs/knowledge_hub directory.
      - verification plan files go to docs/verification_plan.md.
    - Please structure the output as follows:
      - For each file, start with a line "FILE: <file-path>" followed by the content of the file. 
      - End each file content with a line "END FILE".
  """
  

def get_spec_analyst_prompt(additional_context=""):
  return f"""
  {get_master_prompt()}
  You are an expert MIPI CSI-2 Specification Analyst.
  Your task is to thoroughly analyze the provided specification text and extract key information.
  Based on the MIPI CSI-2 v4.0 spec, please generate a Markdown summary for the specific section mentioned.

  {additional_context}

  {file_output_instructions()}
  """

def get_architect_prompt(spec_summary=""):
  return f"""
  {get_master_prompt()}
  You are an expert UVM Architect.
  Your task is to design a high-level architecture for the UVM VIP based on the provided specification summary.
  The architecture should include key components, their interactions, and any relevant design patterns.
  Your output must be a SystemVerilog skeleton file (`.sv`).
  For example: 
    Use `uvm_object_utils` and define a class `csi2_driver`.
    Define a virtual task `drive_cphy_packet(csi2_packet pkt)`.
    Inside the task, use pseudo-code comments to indicate where the logic should go.

    SPECIFICATION SUMMARY:
    ---
    {spec_summary}
    ---

  {file_output_instructions()}
  """

def get_coder_prompt(architecture_file_content):
    # This prompt is specialized for writing code based on an approved architecture.
    return f"""
    {get_master_prompt()}
    You are an expert SystemVerilog/UVM Coder.
    You will be given a UVM architecture file with pseudo-code comments.
    Your task is to replace the pseudo-code with complete, clean, and correct SystemVerilog implementation.
    Adhere strictly to the structure provided.

    ARCHITECTURE SKELETON:
    ---
    {architecture_file_content}
    ---

    {file_output_instructions()}
    """

def get_refinement_prompt(original_content, feedback_content, original_filename=""):
    """Creates a prompt for an agent to refine its previous work based on feedback."""
    return f"""
    {get_master_prompt()}
    You are an expert assistant. Your previous task was to generate a document.
    A human reviewer has provided feedback on your work.
    Your goal is to regenerate the document, correcting it based on the feedback provided.
    You must incorporate the feedback directly into the original content to produce a new, improved version.

    --- PREVIOUS OUTPUT ---
    {original_content}
    --- END PREVIOUS OUTPUT ---

    --- HUMAN FEEDBACK ---
    {feedback_content}
    --- END HUMAN FEEDBACK ---

    Now, provide the full, corrected version of the document.
    
    {file_output_instructions()}

    In this task, it is expected that you only write to the same file as in the original content: {original_filename}. DO NOT WRITE TO OTHER FILES.
    """