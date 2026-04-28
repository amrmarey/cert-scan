import re


def parse_asset_list(lines, default_port=443):
    """Parse asset_list.txt lines into list of {address, port} dicts.

    Handles:
      - Blank lines and # comments (including inline)
      - host:port overrides for IPv4/hostnames
      - IPv6 in bracket notation: [::1] or [::1]:8443
    """
    assets = []
    for line in lines:
        line = re.sub(r'\s*#.*$', '', line).strip()
        if not line:
            continue
        # IPv6 with optional port: [2001:db8::1]:8443 or [2001:db8::1]
        m = re.match(r'^\[([^\]]+)\](?::(\d+))?$', line)
        if m:
            assets.append({'address': m.group(1), 'port': int(m.group(2) or default_port)})
            continue
        # host:port — IPv4 address or hostname with explicit port
        m = re.match(r'^([^:]+):(\d+)$', line)
        if m:
            assets.append({'address': m.group(1), 'port': int(m.group(2))})
            continue
        # Plain host / IP on default port
        assets.append({'address': line, 'port': default_port})
    return assets


class FilterModule:
    def filters(self):
        return {'parse_asset_list': parse_asset_list}
