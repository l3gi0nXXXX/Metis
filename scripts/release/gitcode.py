import argparse
import json
import pathlib
import sys
from typing import Optional
import urllib.error
import urllib.parse
import urllib.request

API_ROOT = "https://api.gitcode.com/api/v5"


def delete_tag(owner: str, repo: str, tag: str, access_token: str) -> tuple[int, bytes]:
    params = urllib.parse.urlencode({"access_token": access_token})
    encoded_tag = urllib.parse.quote(tag, safe="")
    url = f"{API_ROOT}/repos/{owner}/{repo}/tags/{encoded_tag}?{params}"
    request = urllib.request.Request(url, method="DELETE")
    request.add_header("Accept", "*/*")
    try:
        with urllib.request.urlopen(request) as response:
            return response.getcode(), response.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def request_upload_info(owner: str, repo: str, tag: str, access_token: str, file_name: str) -> dict:
    params = urllib.parse.urlencode({
        "access_token": access_token,
        "file_name": file_name,
    })
    url = f"{API_ROOT}/repos/{owner}/{repo}/releases/{tag}/upload_url?{params}"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req) as response:
        body = response.read()
    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Upload info API returned invalid JSON: {body!r}") from exc


def upload_blob(upload_url: str, headers: dict, file_path: pathlib.Path) -> tuple[int, bytes]:
    with file_path.open("rb") as fh:
        data = fh.read()
    request = urllib.request.Request(upload_url, data=data, method="PUT")
    for key, value in headers.items():
        request.add_header(key, value)
    try:
        with urllib.request.urlopen(request) as response:
            return response.getcode(), response.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def create_tag(owner: str, repo: str, tag: str, ref: str, access_token: str) -> tuple[int, bytes]:
    params = urllib.parse.urlencode({"access_token": access_token})
    url = f"{API_ROOT}/repos/{owner}/{repo}/tags?{params}"
    payload = json.dumps({"refs": ref, "tag_name": tag}).encode()
    request = urllib.request.Request(url, data=payload, method="POST")
    request.add_header("Content-Type", "application/json")
    request.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            return response.getcode(), response.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def create_release(
    owner: str,
    repo: str,
    tag: str,
    name: str,
    body: str,
    access_token: str,
) -> tuple[int, bytes]:
    params = urllib.parse.urlencode({"access_token": access_token})
    url = f"{API_ROOT}/repos/{owner}/{repo}/releases?{params}"
    payload = json.dumps(
        {
            "tag_name": tag,
            "name": name,
            "body": body
        }
    ).encode()
    request = urllib.request.Request(url, data=payload, method="POST")
    request.add_header("Content-Type", "application/json")
    request.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            return response.getcode(), response.read()
    except urllib.error.HTTPError as err:
        return err.code, err.read()


def print_result(action: str, status_code: int, payload: Optional[bytes]) -> None:
    print(f"{action} finished with status {status_code}")
    if payload:
        try:
            print(payload.decode())
        except UnicodeDecodeError:
            print(payload)


def upload_asset(
    owner: str,
    repo: str,
    tag: str,
    access_token: str,
    file_path: pathlib.Path,
    remote_name: Optional[str],
) -> None:
    remote = remote_name or file_path.name
    print("Requesting upload URL...", flush=True)
    upload_info = request_upload_info(owner, repo, tag, access_token, remote)

    upload_url = upload_info.get("url")
    headers = upload_info.get("headers")
    if not upload_url or not isinstance(headers, dict):
        print(f"Unexpected upload info payload: {upload_info}", file=sys.stderr)
        sys.exit(1)

    print("Uploading file...", flush=True)
    status_code, payload = upload_blob(upload_url, headers, file_path)
    print_result("Upload", status_code, payload)
    if status_code >= 300:
        sys.exit(1)


def add_repo_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--owner", required=True, help="Repository owner")
    parser.add_argument("--repo", required=True, help="Repository name")
    parser.add_argument("--tag", required=True, help="Tag identifier")
    parser.add_argument("--access-token", required=True, help="GitCode API access token")


def main() -> None:
    parser = argparse.ArgumentParser(description="GitCode release utilities")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.required = True

    release_parser = subparsers.add_parser(
        "release", help="Create tag, release, and upload an asset"
    )
    add_repo_arguments(release_parser)
    release_parser.add_argument(
        "--release-name",
        help="Release name to use when creating a release; defaults to the tag",
    )
    release_parser.add_argument(
        "--release-body",
        default="",
        help="Release notes body to include when creating a release",
    )

    upload_parser = subparsers.add_parser("upload", help="Upload an asset to an existing release")
    upload_parser.add_argument("file", help="Local file to upload")
    add_repo_arguments(upload_parser)
    upload_parser.add_argument("--remote-name", help="Remote file name; defaults to local name")

    delete_parser = subparsers.add_parser("delete-tag", help="Delete a tag from the repository")
    add_repo_arguments(delete_parser)

    args = parser.parse_args()

    if args.command == "delete-tag":
        status_code, payload = delete_tag(args.owner, args.repo, args.tag, args.access_token)
        print_result("Delete tag", status_code, payload)
        if status_code >= 300 and status_code != 404:
            sys.exit(1)
        if status_code == 404:
            print("Tag not found", flush=True)
        return

    if args.command == "upload":
        file_path = pathlib.Path(args.file)
        if not file_path.is_file():
            print(f"File not found: {file_path}", file=sys.stderr)
            sys.exit(1)

        upload_asset(
            args.owner,
            args.repo,
            args.tag,
            args.access_token,
            file_path,
            args.remote_name,
        )
        return

    print("Creating tag...", flush=True)
    status_code, payload = create_tag(
        args.owner,
        args.repo,
        args.tag,
        'main',
        args.access_token,
    )
    print_result("Create tag", status_code, payload)
    if status_code >= 300:
        sys.exit(1)

    print("Creating release...", flush=True)
    status_code, payload = create_release(
        args.owner,
        args.repo,
        args.tag,
        args.release_name,
        args.release_body,
        args.access_token,
    )
    print_result("Create release", status_code, payload)
    if status_code >= 300:
        sys.exit(1)


if __name__ == "__main__":
    main()
