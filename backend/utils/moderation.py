import re
import unicodedata
import urllib.parse
from typing import Optional, Tuple
import requests
import socket
import ipaddress

# Regular expressions for sensitive data patterns
# PHONE_REGEX matches Indian mobile numbers: e.g. +91 9876543210, 98765-43210, 9876543210
PHONE_REGEX = re.compile(r'(?:\+91[\-\s]?)?[6-9]\d{9}|(?:\b\d{5}[\-\s]?\d{5}\b)')
EMAIL_REGEX = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b')
URL_REGEX = re.compile(r'https?://[^\s]+')

BLOCKED_KEYWORDS = [
    "saala", "kamine", "harami", "bhadwa", "chutiya", "gaand", "laund", "randi",
    "abuseword"
]

# Homoglyph translation mapping table (§20 Homoglyph protection)
HOMOGLYPH_MAP = {
    # Cyrillic lookalikes
    'а': 'a', 'е': 'e', 'о': 'o', 'р': 'r', 'с': 'c', 'х': 'x', 'у': 'y', 'і': 'i',
    'ј': 'j', 'ѕ': 's', 'н': 'h', 'т': 't', 'м': 'm', 'к': 'k', 'в': 'b',
    # Greek lookalikes
    'α': 'a', 'β': 'b', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'ζ': 'z', 'η': 'h', 'θ': 'th',
    'ι': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'x', 'ο': 'o', 'π': 'p',
    'ρ': 'r', 'σ': 's', 'τ': 't', 'υ': 'y', 'φ': 'f', 'χ': 'x', 'ψ': 'ps', 'ω': 'o',
    # Fullwidth Latin
    'ａ': 'a', 'ｂ': 'b', 'ｃ': 'c', 'ｄ': 'd', 'ｅ': 'e', 'ｆ': 'f', 'ｇ': 'g',
    'ｈ': 'h', 'ｉ': 'i', 'ｊ': 'j', 'ｋ': 'k', 'ｌ': 'l', 'ｍ': 'm', 'ｎ': 'n',
    'ｏ': 'o', 'ｐ': 'p', 'ｑ': 'q', 'ｒ': 'r', 'ｓ': 's', 'ｔ': 't', 'ｕ': 'u',
    'ｖ': 'v', 'ｗ': 'w', 'ｘ': 'x', 'ｙ': 'y', 'ｚ': 'z'
}

# Standard URL Shorteners to follow
SHORTENER_DOMAINS = {"bit.ly", "tinyurl.com", "t.co", "goo.gl", "rebrand.ly", "is.gd", "tiny.cc"}
# Allowed safe domains list
SAFE_DOMAINS = {"vadodara.local", "google.com", "github.com", "wikipedia.org"}

def resolve_homoglyphs(text: str) -> str:
    """
    Translates visually identical homoglyphs from Cyrillic/Greek scripts to their Latin/ASCII representations.
    """
    return "".join(HOMOGLYPH_MAP.get(char, char) for char in text)

def strip_control_and_zero_width(text: str) -> str:
    """
    Strips zero-width joiners, spaces, direction marks, and control characters.
    """
    control_pattern = re.compile(r'[\u200b-\u200d\ufeff\u0000-\u001f\u007f-\u009f\u202a-\u202e]')
    return control_pattern.sub('', text)

def analyze_phishing_redirects(url: str) -> Tuple[str, bool]:
    """
    🛡️ Multi-Stage Phishing Analysis Pipeline (§22):
    1. Parse URL using strict urllib structures.
    2. Enforce strict HTTPS scheme (reject http/file/data/javascript).
    3. Detect Punycode / IDN Homoglyph Spoofing (check 'xn--' and non-ASCII chars).
    4. Resolve shortened redirect links (follow Location header up to 5 hops).
    5. Perform Domain Reputation check against whitelisted/blacklisted namespaces.
    """
    current_url = url
    try:
        for _ in range(5):
            parsed = urllib.parse.urlparse(current_url)
            
            # 1. Scheme Check
            if parsed.scheme != "https":
                return current_url, False
                
            # 2. Punycode & Non-ASCII Homoglyph Check
            host = parsed.netloc.lower()
            if "xn--" in host or any(ord(c) > 127 for c in host):
                return current_url, False  # High risk punycode phishing domain
                
            # 3. Resolve shortened links
            domain = host.split(":")[0]
            
            # SSRF Guard: Resolve IP and check if it's a private, loopback, or metadata IP
            try:
                ip = socket.gethostbyname(domain)
                ip_obj = ipaddress.ip_address(ip)
                if ip_obj.is_private or ip_obj.is_loopback or ip == "169.254.169.254":
                    return current_url, False # Block SSRF attempts
            except socket.gaierror:
                pass # Proceed to fail safely or try request

            if domain in SHORTENER_DOMAINS:
                res = requests.head(current_url, allow_redirects=False, timeout=3)
                if res.status_code in (301, 302, 307, 308) and "Location" in res.headers:
                    current_url = res.headers["Location"]
                    continue
            break
            
        final_parsed = urllib.parse.urlparse(current_url)
        final_host = final_parsed.netloc.lower().split(":")[0]
        
        # 4. Domain Reputation checks
        # Allow safe domains list, flag unrecognized domains
        if final_host not in SAFE_DOMAINS:
            return current_url, False
            
        return current_url, True
    except Exception as e:
        print(f"Error in phishing verification pipeline: {e}")
        return current_url, False  # Fail-safe closed

def normalize_for_filter(text: str) -> str:
    """
    🛡️ Multi-Stage Unicode Normalization & Hardening Pipeline (§20):
    1. Unicode Normalization (NFKC).
    2. Zero-Width Character Detection and Removal.
    3. Confusable / Homoglyph Translation.
    4. Spacing Stripping.
    5. Casefolding.
    """
    normalized = unicodedata.normalize("NFKC", text)
    stripped_zw = strip_control_and_zero_width(normalized)
    latin_mapped = resolve_homoglyphs(stripped_zw)
    collapsed = re.sub(r"[\s\-_.]+", "", latin_mapped)
    return collapsed.casefold()

def validate_text_content(text: str) -> Optional[str]:
    """
    Validates post or comment text using the multi-stage moderation pipeline.
    Ensures safe content checks while preserving the original unmodified text for safe storage.
    """
    cleaned_text = text.strip()
    
    # 1. Empty Check
    if not cleaned_text:
        return "Content cannot be empty."
        
    # 2. XSS / Script Injection Prevention
    if "<script" in cleaned_text.lower() or "javascript:" in cleaned_text.lower():
        return "Malicious script syntax detected."
        
    # 3. Compile Normalized Text for Moderation Check
    normalized_text = normalize_for_filter(cleaned_text)
    
    # 4. Doxxing Check (Phone numbers scanned on both raw & normalized representation)
    if PHONE_REGEX.search(normalized_text) or PHONE_REGEX.search(cleaned_text):
        return "Sharing phone numbers is strictly prohibited under local safety guidelines."
        
    # 5. Doxxing Check (Emails)
    if EMAIL_REGEX.search(normalized_text) or EMAIL_REGEX.search(cleaned_text):
        return "Sharing email addresses is prohibited to protect user anonymity."
        
    # 6. Phishing Link / Redirect Analysis Pipeline (§22)
    urls = URL_REGEX.findall(cleaned_text)
    for url in urls:
        final_destination, is_safe = analyze_phishing_redirects(url)
        if not is_safe:
            return "Post blocked: Dangerous or unrecognized external link detected."
            
    return None
