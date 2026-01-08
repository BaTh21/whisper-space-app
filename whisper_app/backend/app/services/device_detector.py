import re
from typing import Dict, Any, Optional


class DeviceDetector:
    @staticmethod
    def get_device_info(
        user_agent: Optional[str] = None,
        ip_address: Optional[str] = None
    ) -> Dict[str, Any]:
        info = {
            "device_type": "unknown",
            "browser": "unknown",
            "os": "unknown",
            "device_name": "unknown",
            "user_agent": user_agent,
            "ip_address": ip_address
        }
        
        if not user_agent:
            return info
        
        ua_lower = user_agent.lower()
        
        if "windows" in ua_lower:
            info["os"] = "Windows"
        elif "mac os" in ua_lower or "macos" in ua_lower:
            info["os"] = "macOS"
        elif "linux" in ua_lower:
            info["os"] = "Linux"
        elif "android" in ua_lower:
            info["os"] = "Android"
        elif "ios" in ua_lower or "iphone" in ua_lower:
            info["os"] = "iOS"
        
        if "chrome" in ua_lower and "chromium" not in ua_lower:
            info["browser"] = "Chrome"
        elif "firefox" in ua_lower:
            info["browser"] = "Firefox"
        elif "safari" in ua_lower and "chrome" not in ua_lower:
            info["browser"] = "Safari"
        elif "edge" in ua_lower:
            info["browser"] = "Edge"
        elif "opera" in ua_lower:
            info["browser"] = "Opera"
        
        if any(mobile in ua_lower for mobile in ["mobile", "android", "iphone"]):
            info["device_type"] = "mobile"
            if "iphone" in ua_lower:
                info["device_name"] = "iPhone"
            elif "ipad" in ua_lower:
                info["device_type"] = "tablet"
                info["device_name"] = "iPad"
            elif "android" in ua_lower:
                info["device_name"] = "Android Phone"
        elif "tablet" in ua_lower or "ipad" in ua_lower:
            info["device_type"] = "tablet"
            if "ipad" in ua_lower:
                info["device_name"] = "iPad"
            else:
                info["device_name"] = "Tablet"
        else:
            info["device_type"] = "desktop"
            info["device_name"] = "Desktop/Laptop"
        
        if "samsung" in ua_lower:
            info["device_name"] = "Samsung Device"
        elif "xiaomi" in ua_lower:
            info["device_name"] = "Xiaomi Device"
        elif "huawei" in ua_lower:
            info["device_name"] = "Huawei Device"
        
        return info