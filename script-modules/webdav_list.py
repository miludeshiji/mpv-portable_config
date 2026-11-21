import json
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, unquote_to_bytes, urljoin, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from xml.etree import ElementTree


DAV = "{DAV:}"
PROPFIND = b'<propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>'


def origin(url):
    return url.scheme, url.hostname, url.port or (443 if url.scheme == "https" else 80)


def path_parts(path):
    return [unquote_to_bytes(part) for part in path.rstrip("/").split("/")]


def parse_listing(body, directory):
    xml = ElementTree.fromstring(body)
    if xml.tag != DAV + "multistatus":
        raise ValueError("服务器返回的内容不是 WebDAV 目录列表")

    base = urlsplit(directory)
    base_parts = path_parts(base.path)
    entries = {}
    for response in xml.findall(DAV + "response"):
        href = response.findtext(DAV + "href")
        if not href:
            continue

        try:
            resource = urlsplit(urljoin(directory, href.strip()))
            if resource.username is not None or origin(resource) != origin(base):
                continue
            child_path = resource.path.rstrip("/")
            parent, _, encoded_name = child_path.rpartition("/")
            if not encoded_name or path_parts(parent) != base_parts:
                continue
        except ValueError:
            continue

        for propstat in response.findall(DAV + "propstat"):
            status = propstat.findtext(DAV + "status", "").split()
            resource_type = propstat.find(f"{DAV}prop/{DAV}resourcetype")
            if len(status) > 1 and status[1].startswith("2") and resource_type is not None:
                is_directory = resource_type.find(DAV + "collection") is not None
                suffix = "/" if is_directory else ""
                path = base.path + quote(encoded_name, safe="/%:@!$&'()*+,;=-._~") + suffix
                url = urlunsplit(base._replace(path=path))
                entries[url] = {
                    "name": unquote(encoded_name) + suffix,
                    "path": url,
                    "type": "dir" if is_directory else "file",
                }
                break
    return list(entries.values())


def list_directory(config_path, directory):
    with Path(config_path).open(encoding="utf-8") as config:
        libraries = json.load(config)
    library = max(
        (entry for entry in libraries if directory.startswith(entry["url"])),
        key=lambda entry: len(entry["url"]),
        default=None,
    )
    if library is None:
        raise ValueError("所选目录不属于已配置的 WebDAV 库")

    request = Request(
        directory,
        data=PROPFIND,
        headers={"Depth": "1", "Content-Type": "application/xml; charset=utf-8"},
        method="PROPFIND",
    )
    if library.get("authorization"):
        request.add_unredirected_header("Authorization", library["authorization"])

    with urlopen(request, timeout=15) as response:
        if response.status != 207:
            raise ValueError(f"目录查询返回 HTTP {response.status}，需要 WebDAV 207 响应")
        return parse_listing(response.read(), directory)


def main():
    try:
        result = {"entries": list_directory(*sys.argv[1:])}
    except HTTPError as error:
        messages = {
            401: "用户名或密码有误",
            403: "没有访问权限",
            404: "目录不存在，请检查 WebDAV 地址",
            405: "该地址不支持 PROPFIND，请检查 WebDAV 地址",
        }
        detail = messages.get(error.code, "请检查服务器和目录地址")
        result = {"error": f"WebDAV HTTP {error.code} · {detail}"}
    except (URLError, TimeoutError):
        result = {"error": "无法连接 WebDAV，请检查地址、网络和证书"}
    except (OSError, ValueError, KeyError, TypeError, ElementTree.ParseError):
        result = {"error": "无法读取 WebDAV 目录，请检查库配置和服务器响应"}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
