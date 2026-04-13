import json
import re
import os
import time
import random
import secrets
import hashlib
import base64
import argparse
import logging
from datetime import datetime
import urllib.parse
import urllib.request
import urllib.error
from dataclasses import dataclass
from typing import Any, Dict, Optional, List

from curl_cffi import requests
from faker import Faker

# ==========================================
# 日志配置
# ==========================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


# ==========================================
# 配置区
# ==========================================
# Token 保存目录 (支持 ~ 符号)
SAVE_DIRECTORY = "~/dockers/cli-proxy/openai"

# OAuth 凭证 (一般无需修改)
CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
DEFAULT_REDIRECT_URI = "http://localhost:1455/auth/callback"
DEFAULT_SCOPE = "openid email profile offline_access"


# ==========================================
# Mail.tm 临时邮箱 API
# ==========================================

MAILTM_BASE = "https://api.mail.tm"


def _mailtm_headers(*, token: str = "", use_json: bool = False) -> Dict[str, Any]:
    headers = {"Accept": "application/json"}
    if use_json:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _mailtm_domains(proxies: Any = None) -> List[str]:
    resp = requests.get(
        f"{MAILTM_BASE}/domains",
        headers=_mailtm_headers(),
        proxies=proxies,
        impersonate="chrome",
        timeout=15,
    )
    resp.raise_for_status()
    data = resp.json()
    domains = []
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict):
        items = data.get("hydra:member") or data.get("items") or []
    else:
        items = []

    for item in items:
        if not isinstance(item, dict):
            continue
        domain = str(item.get("domain") or "").strip()
        is_active = item.get("isActive", True)
        is_private = item.get("isPrivate", False)
        if domain and is_active and not is_private:
            domains.append(domain)

    return domains


def get_email_and_token(proxies: Any = None) -> tuple:
    """创建 Mail.tm 邮箱并获取 Bearer Token"""
    try:
        domains = _mailtm_domains(proxies)
        if not domains:
            logger.error("Mail.tm 没有可用域名")
            return "", ""
        domain = random.choice(domains)

        for _ in range(5):
            local = f"oc{secrets.token_hex(5)}"
            email = f"{local}@{domain}"
            password = secrets.token_urlsafe(18)

            create_resp = requests.post(
                f"{MAILTM_BASE}/accounts",
                headers=_mailtm_headers(use_json=True),
                json={"address": email, "password": password},
                proxies=proxies,
                impersonate="chrome",
                timeout=15,
            )

            if create_resp.status_code not in (200, 201):
                continue

            token_resp = requests.post(
                f"{MAILTM_BASE}/token",
                headers=_mailtm_headers(use_json=True),
                json={"address": email, "password": password},
                proxies=proxies,
                impersonate="chrome",
                timeout=15,
            )

            if token_resp.status_code == 200:
                token = str(token_resp.json().get("token") or "").strip()
                if token:
                    return email, token

        logger.error("Mail.tm 邮箱创建成功但获取 Token 失败")
        return "", ""
    except requests.errors.RequestsError as e:
        logger.error(f"请求 Mail.tm API (requests) 出错: {e}")
        return "", ""
    except (json.JSONDecodeError, KeyError) as e:
        logger.error(f"解析 Mail.tm API 响应出错: {e}")
        return "", ""


def get_oai_code(token: str, email: str, proxies: Any = None) -> str:
    """使用 Mail.tm Token 轮询获取 OpenAI 验证码"""
    url_list = f"{MAILTM_BASE}/messages"
    regex = r"(?<!\d)(\d{6})(?!\d)"
    seen_ids: set[str] = set()

    logger.info(f"正在等待邮箱 {email} 的验证码...")

    # 优化：减少等待次数，从 40 次降到 20 次（60 秒）
    for i in range(20):
        try:
            resp = requests.get(
                url_list,
                headers=_mailtm_headers(token=token),
                proxies=proxies,
                impersonate="chrome",
                timeout=15,
            )
            if resp.status_code != 200:
                time.sleep(2)
                continue

            data = resp.json()
            messages = data.get("hydra:member", []) if isinstance(data, dict) else data

            for msg in messages:
                if not isinstance(msg, dict):
                    continue
                msg_id = str(msg.get("id") or "").strip()
                if not msg_id or msg_id in seen_ids:
                    continue
                seen_ids.add(msg_id)

                read_resp = requests.get(
                    f"{MAILTM_BASE}/messages/{msg_id}",
                    headers=_mailtm_headers(token=token),
                    proxies=proxies,
                    impersonate="chrome",
                    timeout=15,
                )
                if read_resp.status_code != 200:
                    continue

                mail_data = read_resp.json()
                sender = str((mail_data.get("from", {}).get("address") or "")).lower()
                subject = str(mail_data.get("subject") or "")
                text = str(mail_data.get("text") or "")
                html = mail_data.get("html") or ""
                if isinstance(html, list):
                    html = "\n".join(str(x) for x in html)
                content = "\n".join([subject, text, str(html)])

                if "openai" not in sender and "openai" not in content.lower():
                    continue

                m = re.search(regex, content)
                if m:
                    logger.info(f"抓到啦！验证码：{m.group(1)}")
                    return m.group(1)
        except (requests.errors.RequestsError, json.JSONDecodeError, KeyError) as e:
            logger.warning(f"轮询邮件时发生临时错误：{e}")
            pass

        time.sleep(3)
        if (i + 1) % 10 == 0:
            logger.info(f"已等待 { (i + 1) * 3 } 秒...")


    logger.error("超时（60 秒），未收到验证码")
    return ""


# ==========================================
# OAuth 授权与辅助函数
# ==========================================

AUTH_URL = "https://auth.openai.com/oauth/authorize"
TOKEN_URL = "https://auth.openai.com/oauth/token"


def _b64url_no_pad(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _sha256_b64url_no_pad(s: str) -> str:
    return _b64url_no_pad(hashlib.sha256(s.encode("ascii")).digest())


def _random_state(nbytes: int = 16) -> str:
    return secrets.token_urlsafe(nbytes)


def _pkce_verifier() -> str:
    return secrets.token_urlsafe(64)


def _parse_callback_url(callback_url: str) -> Dict[str, Any]:
    candidate = callback_url.strip()
    if not candidate:
        return {"code": "", "state": "", "error": "", "error_description": ""}

    if "://" not in candidate:
        if candidate.startswith("?"):
            candidate = f"http://localhost{candidate}"
        elif any(ch in candidate for ch in "/?#") or ":" in candidate:
            candidate = f"http://{candidate}"
        elif "=" in candidate:
            candidate = f"http://localhost/?{candidate}"

    parsed = urllib.parse.urlparse(candidate)
    query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
    fragment = urllib.parse.parse_qs(parsed.fragment, keep_blank_values=True)

    for key, values in fragment.items():
        if key not in query or not query[key] or not (query[key][0] or "").strip():
            query[key] = values

    def get1(k: str) -> str:
        v = query.get(k, [""])
        return (v[0] or "").strip()

    code = get1("code")
    state = get1("state")
    error = get1("error")
    error_description = get1("error_description")

    if code and not state and "#" in code:
        code, state = code.split("#", 1)

    if not error and error_description:
        error, error_description = error_description, ""

    return {
        "code": code,
        "state": state,
        "error": error,
        "error_description": error_description,
    }


def _decode_base64_json(segment: str) -> Dict[str, Any]:
    """辅助函数：解码 Base64 URL 编码的 JSON 字符串"""
    raw = (segment or "").strip()
    if not raw:
        return {}
    pad = "=" * ((4 - (len(raw) % 4)) % 4)
    try:
        decoded = base64.urlsafe_b64decode((raw + pad).encode("ascii"))
        return json.loads(decoded.decode("utf-8"))
    except (ValueError, TypeError, json.JSONDecodeError):
        return {}


def _jwt_claims_no_verify(id_token: str) -> Dict[str, Any]:
    if not id_token or id_token.count(".") < 2:
        return {}
    return _decode_base64_json(id_token.split(".")[1])


def _decode_jwt_segment(seg: str) -> Dict[str, Any]:
    return _decode_base64_json(seg)


def _to_int(v: Any) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def _post_form(url: str, data: Dict[str, str], timeout: int = 30) -> Dict[str, Any]:
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            if resp.status != 200:
                raise RuntimeError(
                    f"token exchange failed: {resp.status}: {raw.decode('utf-8', 'replace')}"
                )
            return json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        raise RuntimeError(
            f"token exchange failed: {exc.code}: {raw.decode('utf-8', 'replace')}"
        ) from exc


@dataclass(frozen=True)
class OAuthStart:
    auth_url: str
    state: str
    code_verifier: str
    redirect_uri: str


def generate_oauth_url(
    *, redirect_uri: str = DEFAULT_REDIRECT_URI, scope: str = DEFAULT_SCOPE
) -> OAuthStart:
    state = _random_state()
    code_verifier = _pkce_verifier()
    code_challenge = _sha256_b64url_no_pad(code_verifier)

    params = {
        "client_id": CLIENT_ID,
        "response_type": "code",
        "redirect_uri": redirect_uri,
        "scope": scope,
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
        "prompt": "login",
        "id_token_add_organizations": "true",
        "codex_cli_simplified_flow": "true",
    }
    auth_url = f"{AUTH_URL}?{urllib.parse.urlencode(params)}"
    return OAuthStart(
        auth_url=auth_url,
        state=state,
        code_verifier=code_verifier,
        redirect_uri=redirect_uri,
    )


def submit_callback_url(
    *,
    callback_url: str,
    expected_state: str,
    code_verifier: str,
    redirect_uri: str = DEFAULT_REDIRECT_URI,
) -> str:
    cb = _parse_callback_url(callback_url)
    if cb["error"]:
        desc = cb["error_description"]
        raise RuntimeError(f"oauth error: {cb['error']}: {desc}".strip())

    if not cb["code"]:
        raise ValueError("callback url missing ?code=")
    if not cb["state"]:
        raise ValueError("callback url missing ?state=")
    if cb["state"] != expected_state:
        raise ValueError("state mismatch")

    token_resp = _post_form(
        TOKEN_URL,
        {
            "grant_type": "authorization_code",
            "client_id": CLIENT_ID,
            "code": cb["code"],
            "redirect_uri": redirect_uri,
            "code_verifier": code_verifier,
        },
    )

    access_token = (token_resp.get("access_token") or "").strip()
    refresh_token = (token_resp.get("refresh_token") or "").strip()
    id_token = (token_resp.get("id_token") or "").strip()
    expires_in = _to_int(token_resp.get("expires_in"))

    claims = _jwt_claims_no_verify(id_token)
    email = str(claims.get("email") or "").strip()
    auth_claims = claims.get("https://api.openai.com/auth") or {}
    account_id = str(auth_claims.get("chatgpt_account_id") or "").strip()

    now = int(time.time())
    expired_rfc3339 = time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime(now + max(expires_in, 0))
    )
    now_rfc3339 = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))

    config = {
        "id_token": id_token,
        "access_token": access_token,
        "refresh_token": refresh_token,
        "account_id": account_id,
        "last_refresh": now_rfc3339,
        "email": email,
        "type": "codex",
        "expired": expired_rfc3339,
    }

    return json.dumps(config, ensure_ascii=False, separators=(",", ":"))


# ==========================================
# 核心注册逻辑
# ==========================================


def run(
    proxy: Optional[str],
    name: str,
    birthdate: str,
) -> Optional[str]:
    proxies: Any = None
    if proxy:
        proxies = {"http": proxy, "https": proxy}

    s = requests.Session(proxies=proxies, impersonate="chrome")

    try:
        # 网络检查 - 增加重试机制
        max_retries = 3
        for attempt in range(max_retries):
            try:
                trace = s.get("https://cloudflare.com/cdn-cgi/trace", timeout=15)
                trace.raise_for_status()
                trace_text = trace.text
                loc_re = re.search(r"^loc=(.+)$", trace_text, re.MULTILINE)
                loc = loc_re.group(1) if loc_re else "N/A"
                logger.info(f"当前 IP 所在地：{loc}")
                if loc in ["CN", "HK"]:
                    raise RuntimeError("检查代理哦 w - 所在地不支持")
                break  # 成功则退出重试
            except requests.errors.RequestsError as e:
                if attempt < max_retries - 1:
                    logger.warning(f"网络连接检查失败 (尝试 {attempt + 1}/{max_retries}): {e}")
                    logger.info("请确认代理配置正确（使用 --proxy 参数）")
                    time.sleep(2)
                else:
                    logger.error(f"网络连接检查失败（已重试 {max_retries} 次）: {e}")
                    logger.error("提示：如果在中国大陆，请使用代理，例如：--proxy http://127.0.0.1:7890")
                    return None
    except Exception as e:
        logger.error(f"网络连接检查发生未知错误：{e}")
        return None

    email, dev_token = get_email_and_token(proxies)
    if not email or not dev_token:
        return None
    logger.info(f"成功获取 Mail.tm 邮箱与授权: {email}")

    oauth = generate_oauth_url()
    url = oauth.auth_url

    try:
        s.get(url, timeout=15).raise_for_status()
        did = s.cookies.get("oai-did")
        logger.info(f"Device ID: {did}")

        signup_body = f'{{"username":{{"value":"{email}","kind":"email"}},"screen_hint":"signup"}}'
        sen_req_body = f'{{"p":"","id":"{did}","flow":"authorize_continue"}}'

        sen_resp = s.post(
            "https://sentinel.openai.com/backend-api/sentinel/req",
            headers={
                "origin": "https://sentinel.openai.com",
                "referer": "https://sentinel.openai.com/backend-api/sentinel/frame.html?sv=20260219f9f6",
                "content-type": "text/plain;charset=UTF-8",
            },
            data=sen_req_body,
            timeout=15,
        )
        sen_resp.raise_for_status()
        sen_token = sen_resp.json()["token"]
        sentinel = f'{{"p": "", "t": "", "c": "{sen_token}", "id": "{did}", "flow": "authorize_continue"}}'

        signup_resp = s.post(
            "https://auth.openai.com/api/accounts/authorize/continue",
            headers={
                "referer": "https://auth.openai.com/create-account",
                "accept": "application/json",
                "content-type": "application/json",
                "openai-sentinel-token": sentinel,
            },
            data=signup_body,
        )
        signup_resp.raise_for_status()
        logger.info(f"提交注册表单状态：{signup_resp.status_code}")
        
        # 获取 continue_url 并访问它以进入正确的授权步骤
        signup_data = signup_resp.json()
        continue_url = str(signup_data.get("continue_url") or "").strip()
        if not continue_url:
            logger.error("signup 响应中缺少 continue_url")
            return None
        
        logger.info(f"获取到 continue_url: {continue_url}")
        
        # 访问 continue_url 以进入邮箱验证步骤
        continue_resp = s.get(continue_url, allow_redirects=True, timeout=15)
        logger.info(f"访问 continue_url 状态：{continue_resp.status_code}")
        
        # 关键调试：检查响应内容，看看页面要求什么
        try:
            html_content = continue_resp.text
            # 检查是否有人机验证
            if "captcha" in html_content.lower() or "turnstile" in html_content.lower():
                logger.warning("检测到人机验证要求，可能需要浏览器交互")
            # 检查是否有密码设置要求
            if "password" in html_content.lower() and "set" in html_content.lower():
                logger.warning("检测到密码设置要求")
            # 提取页面标题或关键信息
            title_match = re.search(r'<title[^>]*>([^<]+)</title>', html_content)
            if title_match:
                logger.info(f"页面标题：{title_match.group(1).strip()}")
            
            # 关键修复：从 HTML 中提取 CSRF token 或表单 action URL
            csrf_match = re.search(r'name=["\']csrf_token["\']\s+value=["\']([^"\']+)["\']', html_content)
            if csrf_match:
                csrf_token = csrf_match.group(1)
                logger.info(f"检测到 CSRF token: {csrf_token[:20]}...")
            
            # 查找表单的 action URL
            action_match = re.search(r'<form[^>]+action=["\']([^"\']+)["\']', html_content)
            if action_match:
                form_action = action_match.group(1)
                logger.info(f"检测到表单提交地址：{form_action}")
        except Exception as e:
            logger.warning(f"解析 HTML 内容失败：{e}")
        
        # 关键修复：也许不应该调用 email-otp/send API，而是先完成密码设置
        # 从 HTML 中提取表单信息并模拟提交
        logger.info("尝试从 HTML 中提取表单并提交密码...")
        
        # 尝试直接 POST 到密码设置页面（模拟表单提交）
        password = secrets.token_urlsafe(12) + "A1!"
        logger.info(f"生成随机密码，尝试设置...")
        
        # 使用表单格式提交（而不是 JSON）
        password_form_resp = s.post(
            continue_url,
            headers={
                "referer": "https://auth.openai.com/create-account",
                "accept": "application/json",
                "content-type": "application/x-www-form-urlencoded",
            },
            data=f"password={urllib.parse.quote(password)}",
        )
        logger.info(f"密码表单提交状态：{password_form_resp.status_code}")
        
        # 检查响应
        if password_form_resp.status_code == 200:
            try:
                result = password_form_resp.json()
                logger.info(f"密码设置响应：{result}")
            except:
                logger.info(f"密码设置响应（非 JSON）: {password_form_resp.text[:200]}")
        
        # 现在应该可以发送验证码了
        otp_resp = s.post(
            "https://auth.openai.com/api/accounts/email-otp/send",
            headers={
                "referer": continue_url,
                "accept": "application/json",
                "content-type": "application/json",
            },
        )
        if otp_resp.status_code == 200:
            logger.info(f"验证码已发送：{otp_resp.status_code}")
        else:
            logger.warning(f"验证码发送状态：{otp_resp.status_code}")
            try:
                error_detail = otp_resp.json()
                logger.error(f"验证码发送失败详情：{json.dumps(error_detail, indent=2, ensure_ascii=False)}")
                # 检查是否是邮箱已存在的问题
                if "already exists" in str(error_detail):
                    logger.error("该邮箱可能已经注册过，请等待下一轮使用新邮箱")
                # 检查是否需要手机验证
                if "phone" in str(error_detail).lower():
                    logger.warning("检测到可能需要手机验证")
            except Exception as e:
                logger.error(f"解析错误响应失败：{e}")
                logger.error(f"原始响应：{otp_resp.text}")
            
            # 关键修复：如果邮箱验证不可用，尝试直接返回错误，不要死等
            if otp_resp.status_code == 400:
                logger.error("邮箱验证 API 返回 400，可能该方式已不可用，建议检查 OpenAI 最新注册政策")
                return None  # 直接返回失败，不要继续等待不存在的验证码

        code = get_oai_code(dev_token, email, proxies)
        if not code:
            return None
        
        code_body = f'{{"code":"{code}"}}'
        code_resp = s.post(
            "https://auth.openai.com/api/accounts/email-otp/validate",
            headers={
                "referer": "https://auth.openai.com/email-verification",
                "accept": "application/json",
                "content-type": "application/json",
            },
            data=code_body,
        )
        code_resp.raise_for_status()
        logger.info(f"验证码校验状态：{code_resp.status_code}")
                
        # 关键修复：验证码验证成功后，先设置密码，再创建账户
        password = secrets.token_urlsafe(12) + "A1!"
        logger.info("正在设置账户密码...")
                
        password_resp = s.post(
            "https://auth.openai.com/api/accounts/password",
            headers={
                "referer": "https://auth.openai.com/create-account/password",
                "accept": "application/json",
                "content-type": "application/json",
            },
            json={"password": password},
        )
        logger.info(f"密码设置状态：{password_resp.status_code}")
                
        # 如果密码设置失败，记录错误但继续尝试
        if password_resp.status_code != 200:
            try:
                error_detail = password_resp.json()
                logger.warning(f"密码设置失败（可能不需要此步骤）: {error_detail}")
            except:
                logger.warning(f"密码设置响应异常：{password_resp.text}")
        
        create_account_body = f'{{"name":"{name}","birthdate":"{birthdate}"}}'
        create_account_resp = s.post(
            "https://auth.openai.com/api/accounts/create_account",
            headers={
                "referer": "https://auth.openai.com/about-you",
                "accept": "application/json",
                "content-type": "application/json",
            },
            data=create_account_body,
        )
        create_account_resp.raise_for_status()
        logger.info(f"账户创建状态：{create_account_resp.status_code}")

        auth_cookie = s.cookies.get("oai-client-auth-session")
        if not auth_cookie:
            raise ValueError("未能获取到授权 Cookie")

        auth_json = _decode_jwt_segment(auth_cookie.split(".")[0])
        workspaces = auth_json.get("workspaces", [])
        if not workspaces:
            raise ValueError("授权 Cookie 里没有 workspace 信息")
        workspace_id = str(workspaces[0].get("id") or "").strip()
        if not workspace_id:
            raise ValueError("无法解析 workspace_id")

        select_body = f'{{"workspace_id":"{workspace_id}"}}'
        select_resp = s.post(
            "https://auth.openai.com/api/accounts/workspace/select",
            headers={
                "referer": "https://auth.openai.com/sign-in-with-chatgpt/codex/consent",
                "content-type": "application/json",
            },
            data=select_body,
        )
        select_resp.raise_for_status()
        continue_url = str(select_resp.json().get("continue_url") or "").strip()
        if not continue_url:
            raise ValueError("workspace/select 响应里缺少 continue_url")

        current_url = continue_url
        for _ in range(6):
            final_resp = s.get(current_url, allow_redirects=False, timeout=15)
            location = final_resp.headers.get("Location") or ""

            if final_resp.status_code not in [301, 302, 303, 307, 308] or not location:
                break

            next_url = urllib.parse.urljoin(current_url, location)
            if "code=" in next_url and "state=" in next_url:
                return submit_callback_url(
                    callback_url=next_url,
                    code_verifier=oauth.code_verifier,
                    redirect_uri=oauth.redirect_uri,
                    expected_state=oauth.state,
                )
            current_url = next_url

        raise RuntimeError("未能在重定向链中捕获到最终 Callback URL")

    except requests.errors.RequestsError as e:
        logger.error(f"注册流程中的网络请求失败: {e}")
        if e.response:
            logger.error(f"响应内容: {e.response.text}")
        return None
    except (KeyError, ValueError, json.JSONDecodeError) as e:
        logger.error(f"处理注册流程中的数据时出错: {e}")
        return None
    except RuntimeError as e:
        logger.error(f"注册流程中发生运行时错误: {e}")
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenAI 自动注册脚本")
    parser.add_argument(
        "--proxy", default=None, help="代理地址，如 http://127.0.0.1:7890"
    )
    parser.add_argument("--once", action="store_true", help="只运行一次")
    parser.add_argument("--sleep-min", type=int, default=5, help="循环模式最短等待秒数")
    parser.add_argument(
        "--sleep-max", type=int, default=30, help="循环模式最长等待秒数"
    )
    parser.add_argument(
        "--name", default=None, help="注册时使用的用户名 (默认随机生成)"
    )
    parser.add_argument(
        "--birthdate", default=None, help="注册时使用的生日 (YYYY-MM-DD, 默认随机生成)"
    )
    args = parser.parse_args()

    # 处理保存目录
    save_dir = os.path.expanduser(SAVE_DIRECTORY)
    os.makedirs(save_dir, exist_ok=True)

    fake = Faker()
    name = args.name
    birthdate = args.birthdate

    sleep_min = max(1, args.sleep_min)
    sleep_max = max(sleep_min, args.sleep_max)

    count = 0
    logger.info("Yasal's Seamless OpenAI Auto-Registrar Started for ZJH")

    while True:
        count += 1
        logger.info(f">>> 开始第 {count} 次注册流程 <<<")

        # 如果每次循环都想用新的随机信息，则在此处生成
        current_name = name or fake.name()
        current_birthdate = birthdate or fake.date_of_birth(minimum_age=18, maximum_age=40).strftime("%Y-%m-%d")
        
        logger.info(f"使用信息: Name\u003d{current_name}, Birthdate\u003d{current_birthdate}")

        try:
            token_json = run(args.proxy, current_name, current_birthdate)

            if token_json:
                try:
                    t_data = json.loads(token_json)
                    fname_email = t_data.get("email", "unknown").replace("@", "_")
                    file_name = f"token_{fname_email}_{int(time.time())}.json"
                    full_path = os.path.join(save_dir, file_name)

                    with open(full_path, "w", encoding="utf-8") as f:
                        f.write(token_json)

                    logger.info(f"成功! Token 已保存至: {full_path}")
                except (json.JSONDecodeError, IOError) as e:
                    logger.error(f"保存 Token 文件失败: {e}")
            else:
                logger.warning("本次注册失败。")

        except Exception as e:
            logger.critical(f"发生未捕获的严重异常: {e}", exc_info=True)

        if args.once:
            break

        wait_time = random.randint(sleep_min, sleep_max)
        logger.info(f"休息 {wait_time} 秒...")
        time.sleep(wait_time)


if __name__ == "__main__":
    main()
