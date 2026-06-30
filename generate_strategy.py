import os
import google.generativeai as genai

# 1. Retrieve the secure API Key
api_key = os.environ.get("GEMINI_API_KEY")
if not api_key:
    raise ValueError("ERROR: GEMINI_API_KEY environment variable is not set! Run: export GEMINI_API_KEY='your_actual_key'")

# 2. Configure the Gemini API connection
genai.configure(api_key=api_key)

# 3. We use 'gemini-3.5-flash' for optimized, fast code generation
model = genai.GenerativeModel('gemini-3.5-flash')

prompt = """
Write a complete, clean, production-ready MQL5 Expert Advisor (.mq5) for MT5.
- Target: EURUSD or GBPUSD on H1 charts.
- Account Size: Strictly $50. 
- Money Management: Calculate lot sizes dynamically aiming for 1% risk per trade. If the math calculates a lot size below 0.01, force it strictly to default to 0.01 lots so the broker doesn't reject it.
- Risk management: Must include an explicit Stop Loss and a Take Profit targeting at least a 1:1.5 Risk-to-Reward ratio.
- Strategy: Implement a robust, clean mechanical entry rule using a Moving Average crossover or RSI deviations on a bar-close basis.

Output ONLY the raw MQL5 source code. Do not wrap it in any introductions or conversational markdown outside the code block. Start directly with the properties and code structure.
"""

print("🧠 Connecting to Gemini to generate the MQL5 script...")
try:
    response = model.generate_content(prompt)
    raw_code = response.text

    # Strip markdown fence blocks if returned by the API
    if raw_code.startswith("```"):
        lines = raw_code.splitlines()
        if lines[0].startswith("```"): 
            lines = lines[1:]
        if lines[-1].startswith("```"): 
            lines = lines[:-1]
        raw_code = "\n".join(lines)

    output_filename = "ExpertAdvisor.mq5"
    with open(output_filename, "w", encoding="utf-8") as f:
        f.write(raw_code.strip())

    print(f"✅ Success! Your autonomous strategy is saved to {output_filename}")

except Exception as e:
    print(f"❌ Generation failed: {str(e)}")
