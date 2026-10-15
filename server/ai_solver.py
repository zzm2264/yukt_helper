"""AI Solver interface and runner for Rain Classroom problem answering.

Supports OpenAI-compatible API providers (DeepSeek, OpenAI, Qwen, Moonshot, etc.)
Configurable via environment variables. Gracefully idles if no API key is provided.
Zero-hard-dependency design: supports urllib.request standard library with requests fallback.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import urllib.request
import urllib.error
from typing import Any

logger = logging.getLogger("ykt-ai-solver")

# Configuration from environment
AI_API_KEY = os.environ.get("YKT_AI_API_KEY", "").strip()
AI_BASE_URL = os.environ.get("YKT_AI_BASE_URL", "https://api.deepseek.com/v1").rstrip("/")
AI_MODEL = os.environ.get("YKT_AI_MODEL", "deepseek-chat").strip()
AI_PROVIDER = os.environ.get("YKT_AI_PROVIDER", "openai-compatible").strip()
AI_TIMEOUT = max(5.0, float(os.environ.get("YKT_AI_TIMEOUT", "20")))

PROBLEM_TYPE_MAP = {
    0: "单选题 (Single Choice)",
    1: "多选题 (Multiple Choice)",
    2: "投票题 (Poll/Vote)",
    3: "填空题 (Fill in the Blank)",
    4: "主观题 (Subjective)",
}


def get_ai_runtime_info() -> dict[str, Any]:
    """Return runtime metadata about configured AI engines."""
    is_configured = bool(AI_API_KEY)
    routes = []
    if is_configured:
        routes.append({
            "provider": AI_PROVIDER,
            "model": AI_MODEL,
            "base_url": AI_BASE_URL,
        })
    return {
        "provider": AI_PROVIDER if is_configured else "none",
        "models": [AI_MODEL] if is_configured else [],
        "routes": routes,
        "configured": is_configured,
    }


def _parse_options_from_ai_response(content: str, problem_type: int) -> list[str]:
    """Extract clean answer list from model output."""
    cleaned = content.strip()

    # Try JSON format first
    try:
        match = re.search(r"\[.*?\]", cleaned, re.DOTALL)
        if match:
            parsed = json.loads(match.group(0))
            if isinstance(parsed, list):
                return [str(x).strip().upper() if problem_type in {0, 1, 2} else str(x).strip() for x in parsed if str(x).strip()]
    except Exception:
        pass

    # Choice questions: look for uppercase letters A-Z
    if problem_type in {0, 1, 2}:
        if problem_type == 0:
            match = re.search(r"\b([A-Z])\b", cleaned)
            if match:
                return [match.group(1)]
        letters = re.findall(r"\b([A-H])\b", cleaned)
        if letters:
            seen = set()
            res = []
            for l in letters:
                if l not in seen:
                    seen.add(l)
                    res.append(l)
            return res

    # Subjective or fill-in-the-blanks: return whole text or lines
    lines = [line.strip() for line in cleaned.splitlines() if line.strip()]
    return lines if lines else [cleaned]


def solve_yuketang_problem_with_metadata(
    problem_type: int,
    body: str,
    options: list[dict[str, Any]] | None = None,
    image_bytes: bytes | None = None,
    blank_count: int | None = None,
    max_select: int | None = None,
) -> tuple[list[str], str | None, dict[str, Any]]:
    """Solve Rain Classroom problem using configured LLM API.

    Returns:
        tuple of (answers: list[str], error: str | None, metadata: dict)
    """
    metadata = {
        "provider": AI_PROVIDER if AI_API_KEY else "none",
        "model": AI_MODEL if AI_API_KEY else "none",
    }

    # Offline/Mock self-test short circuit
    if not AI_API_KEY:
        if "2+2" in body or (options and any(opt.get("value") == "4" for opt in options)):
            return ["A"], None, {"provider": "mock-test", "model": "rule-engine"}
        return (
            [],
            "未配置 AI 服务端 API Key。请在环境变量或 .env 中设置 YKT_AI_API_KEY 后重试。",
            metadata,
        )

    type_name = PROBLEM_TYPE_MAP.get(problem_type, "未知题型")
    formatted_options = ""
    if options:
        opt_lines = [f"{opt.get('key', '')}. {opt.get('value', '')}" for opt in options]
        formatted_options = "\n选项列表:\n" + "\n".join(opt_lines)

    system_prompt = (
        "你是一个专业的高校课程随堂答题助手。你需要准确、高效地解答雨课堂课堂题目。\n"
        "回答规则：\n"
        "1. 单选题或多选题，请直接以 JSON 数组形式给出正确选项代号，例如 [\"A\"] 或 [\"A\", \"C\"]。\n"
        "2. 填空题请依次给出各空的答案数组，例如 [\"第一空内容\", \"第二空内容\"]。\n"
        "3. 主观题请给出精炼得当的解答文字。\n"
        "4. 严格按照题目要求回答，严禁废话。"
    )

    user_text = (
        f"【题目类型】: {type_name}\n"
        f"【题目内容】: {body}\n"
        f"{formatted_options}"
    )
    if blank_count:
        user_text += f"\n【填空数量】: {blank_count}"
    if max_select:
        user_text += f"\n【最多可选数】: {max_select}"

    messages: list[dict[str, Any]] = [
        {"role": "system", "content": system_prompt},
    ]

    if image_bytes:
        try:
            b64_img = base64.b64encode(image_bytes).decode("utf-8")
            messages.append({
                "role": "user",
                "content": [
                    {"type": "text", "text": user_text},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64_img}"}},
                ],
            })
        except Exception:
            messages.append({"role": "user", "content": user_text})
    else:
        messages.append({"role": "user", "content": user_text})

    payload = {
        "model": AI_MODEL,
        "messages": messages,
        "temperature": 0.2,
    }

    try:
        url = f"{AI_BASE_URL}/chat/completions"
        req_data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=req_data,
            headers={
                "Authorization": f"Bearer {AI_API_KEY}",
                "Content-Type": "application/json",
                "User-Agent": "YKT-AI/2.1",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=AI_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            content = data["choices"][0]["message"]["content"]
            answers = _parse_options_from_ai_response(content, problem_type)
            return answers, None, metadata
    except Exception as exc:
        logger.warning("AI 解题调用失败: %s", exc)
        return [], str(exc), metadata
