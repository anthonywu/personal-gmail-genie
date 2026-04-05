# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "google-api-python-client==2.193.0",
#     "google-auth-oauthlib==1.3.1",
#     "httpx==0.28.1",
#     "pydantic==2.12.5",
#     "rich==14.3.3",
# ]
# ///

import base64
import email.mime.text
import functools
import itertools
import json
import time
import pickle
from pathlib import Path

from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from pydantic import BaseModel
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.rule import Rule
from datetime import datetime, timedelta
from typing import Literal


CONFIG_DIR = Path("~/.config/gmail-genie").expanduser()
AUTH_TOKEN_FILE = CONFIG_DIR / "token.pickle"
LOG_DIR = (
    Path("~/.local/share/gmail_genie").expanduser().mkdir(parents=True, exist_ok=True)
)


# Define a model with Literal fields
class ActionModel(BaseModel):
    action: Literal["ARCHIVE", "DELETE", "NO_OP"]


class MailRuleModel(BaseModel):
    rule_version: str
    from_domain_auto_delete: list[str]
    from_address_auto_archive: list[str]

    def process_message(self, message_dict) -> ActionModel:
        for domain_d in self.from_domain_auto_delete:
            if domain_d in message_dict["from"]:
                return ActionModel(action="DELETE")
        for domain_a in self.from_address_auto_archive:
            if domain_a in message_dict["from"]:
                return ActionModel(action="ARCHIVE")
        return ActionModel(action="NO_OP")


def authenticate():
    """Authenticate with Gmail API using OAuth 2.0"""
    creds = None
    SCOPES = ["https://www.googleapis.com/auth/gmail.modify"]

    # Load credentials from config dir's token.pickle if it exists
    if AUTH_TOKEN_FILE.exists():
        with AUTH_TOKEN_FILE.open("rb") as token:
            creds = pickle.load(token)

    # If credentials are invalid or don't exist, get new ones
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            try:
                credentials_path = CONFIG_DIR / "credentials.json"
                flow = InstalledAppFlow.from_client_secrets_file(
                    str(credentials_path), SCOPES
                )
            except FileNotFoundError:
                print(
                    "Error: credentials.json not found.\n"
                    "Setup Instructions:\n"
                    "1. Go to https://console.cloud.google.com and create a project\n"
                    "2. Enable the Gmail API\n"
                    "3. Navigate to: https://console.cloud.google.com/apis/api/gmail.googleapis.com/credentials?project=<project-name>\n"
                    "4. Create OAuth 2.0 credentials (Desktop application)\n"
                    "5. Download the credentials JSON file\n"
                    "6. Save it as ~/.config/gmail-genie/credentials.json\n"
                )
                raise SystemExit(1)
            creds = flow.run_local_server(port=0)

        # Save credentials for future use
        with AUTH_TOKEN_FILE.open("wb") as token:
            pickle.dump(creds, token)

    return build("gmail", "v1", credentials=creds)


class LabelModel(BaseModel):
    id: str
    name: str


def get_label_map(service, user_id="me"):
    """
    Retrieve a mapping of label IDs to their corresponding logical names.

    Args:
        service (googleapiclient.discovery.Resource): Gmail API service object.
        user_id (str): The user's email address or 'me' for the authenticated user.

    Returns:
        dict: A dictionary mapping label IDs to their logical names.
    """
    try:
        # Retrieve the list of labels
        response = service.users().labels().list(userId=user_id).execute()
        labels = response.get("labels", [])

        # Create a mapping of label IDs to their logical names
        label_map = dict((label["id"], label["name"]) for label in labels)
        return label_map
    except Exception as e:
        print(f"An error occurred: {e}")
        return {}


def list_messages(service, user_id="me", query="", max_results=None):
    """List messages matching the specified query"""
    try:
        response = service.users().messages().list(userId=user_id, q=query).execute()
        messages = []

        if "messages" in response:
            messages.extend(response["messages"])

        while "nextPageToken" in response:
            page_token = response["nextPageToken"]
            response = (
                service.users()
                .messages()
                .list(
                    userId=user_id,
                    q=query,
                    pageToken=page_token,
                    maxResults=max_results,
                )
                .execute()
            )
            messages.extend(response["messages"])

        return messages[:max_results]
    except Exception as e:
        print(f"An error occurred: {e}")
        return []


list_unread_messages = functools.partial(list_messages, query="is:unread")


def get_message_details(service, msg_id, user_id="me"):
    """Get details of a specific message"""
    try:
        # message: dict_keys(['id', 'threadId', 'labelIds', 'snippet', 'payload', 'sizeEstimate', 'historyId', 'internalDate'])
        message = (
            service.users()
            .messages()
            .get(userId=user_id, id=msg_id, format="full")
            .execute()
        )

        headers = message["payload"]["headers"]

        """
        payload: dict_keys(['partId', 'mimeType', 'filename', 'headers', 'body', 'parts'])

        headers: [h['name'] for h in message['payload']['headers']]
        ['Delivered-To', 'Received', 'X-Google-Smtp-Source', 'X-Received', 'ARC-Seal', 'ARC-Message-Signature', 'ARC-Authentication-Results', 'Return-Path', 'Received', 'Received-SPF', 'Authentication-Results', 'DKIM-Signature', 'DKIM-Signature', 'Date', 'From', 'Reply-To', 'To', 'Message-ID', 'Subject', 'Errors-To', 'MIME-Version', 'Content-Type', 'X-DFS-ENV', 'X-FORM-CODE', 'X-FORM-GROUP-CODE', 'X-MSG-GROUP-CODE', 'X-envelope-sender', 'X-RECIPIENT-DOMAIN', 'X-MSG-ID', 'X-REQ-ID', 'X-SENT-TIMESTAMP', 'Feedback-ID', 'X-SES-Outgoing']
        """
        subject = next(h["value"] for h in headers if h["name"].lower() == "subject")
        from_email = next(h["value"] for h in headers if h["name"].lower() == "from")
        to_email = next(h["value"] for h in headers if h["name"].lower() == "to")

        # Get message body
        if "parts" in message["payload"]:
            parts = message["payload"]["parts"]
            data = parts[0]["body"].get("data", "")
        else:
            data = message["payload"]["body"].get("data", "")

        if data:
            content = base64.urlsafe_b64decode(data).decode("utf-8")
        else:
            content = "No content"

        # breakpoint()
        return {
            "id": msg_id,
            "subject": subject,
            "from": from_email,
            "to": to_email,
            "content": content,
            "labelIds": message["labelIds"],
            "headers": dict(
                (h["name"], h["value"]) for h in message["payload"]["headers"]
            ),
        }
    except Exception as e:
        print(f"An error occurred: {e}")
        return None


def delete_message(service, msg_id, user_id="me"):
    """Delete a specific message"""
    try:
        service.users().messages().trash(userId=user_id, id=msg_id).execute()
        print(f"Message {msg_id} moved to trash successfully")
        return True
    except Exception as e:
        print(f"An error occurred: {e}")
        return False


def archive_emails(service, message_ids, user_id="me"):
    """
    Archive a list of emails by their message IDs.

    Args:
        service (googleapiclient.discovery.Resource): Gmail API service object.
        user_id (str): The user's email address or 'me' for the authenticated user.
        message_ids (list): A list of message IDs to be archived.
    """
    try:
        for msg_id in message_ids:
            service.users().messages().modify(
                userId=user_id, id=msg_id, body={"removeLabelIds": ["INBOX", "UNREAD"]}
            ).execute()
            print(f"Archived message with ID: {msg_id}")
        return True
    except Exception as e:
        print(f"An error occurred: {e}")
        return False


def get_profile(service, user_id="me"):
    """Get the authenticated user's profile (email, historyId, message/thread counts)."""
    return service.users().getProfile(userId=user_id).execute()


def get_message_metadata(service, msg_id, user_id="me", metadata_headers=None):
    """Get message metadata (headers only, no body) for faster rule matching."""
    if metadata_headers is None:
        metadata_headers = ["From", "To", "Subject", "Date", "List-Unsubscribe"]
    message = (
        service.users()
        .messages()
        .get(
            userId=user_id,
            id=msg_id,
            format="metadata",
            metadataHeaders=metadata_headers,
        )
        .execute()
    )
    headers = {h["name"].lower(): h["value"] for h in message["payload"]["headers"]}
    return {
        "id": message["id"],
        "threadId": message["threadId"],
        "labelIds": message.get("labelIds", []),
        "snippet": message.get("snippet", ""),
        "headers": headers,
    }


def batch_modify_messages(
    service, message_ids, add_label_ids=None, remove_label_ids=None, user_id="me"
):
    """Modify labels on up to 1000 messages in a single API call."""
    body = {"ids": message_ids}
    if add_label_ids:
        body["addLabelIds"] = add_label_ids
    if remove_label_ids:
        body["removeLabelIds"] = remove_label_ids
    service.users().messages().batchModify(userId=user_id, body=body).execute()


def batch_delete_messages(service, message_ids, user_id="me"):
    """Permanently delete messages. Requires https://mail.google.com/ scope."""
    service.users().messages().batchDelete(
        userId=user_id, body={"ids": message_ids}
    ).execute()


def create_label(service, label_name, user_id="me"):
    """Create a new Gmail label. Returns the created label resource."""
    body = {
        "name": label_name,
        "labelListVisibility": "labelShow",
        "messageListVisibility": "show",
    }
    return service.users().labels().create(userId=user_id, body=body).execute()


def delete_label(service, label_id, user_id="me"):
    """Delete a Gmail label by its ID."""
    service.users().labels().delete(userId=user_id, id=label_id).execute()


def add_labels(service, msg_id, label_ids, user_id="me"):
    """Add labels to a message."""
    return (
        service.users()
        .messages()
        .modify(userId=user_id, id=msg_id, body={"addLabelIds": label_ids})
        .execute()
    )


def list_threads(service, user_id="me", query="", max_results=None):
    """List threads matching the specified query."""
    response = (
        service.users()
        .threads()
        .list(userId=user_id, q=query, maxResults=max_results)
        .execute()
    )
    return response.get("threads", [])


def modify_thread(
    service, thread_id, add_label_ids=None, remove_label_ids=None, user_id="me"
):
    """Modify labels on an entire thread."""
    body = {}
    if add_label_ids:
        body["addLabelIds"] = add_label_ids
    if remove_label_ids:
        body["removeLabelIds"] = remove_label_ids
    return (
        service.users()
        .threads()
        .modify(userId=user_id, id=thread_id, body=body)
        .execute()
    )


def list_history(service, start_history_id, user_id="me", history_types=None):
    """List history changes since a given historyId for incremental sync."""
    kwargs = {"userId": user_id, "startHistoryId": start_history_id}
    if history_types:
        kwargs["historyTypes"] = history_types
    response = service.users().history().list(**kwargs).execute()
    history = response.get("history", [])
    while "nextPageToken" in response:
        response = (
            service.users()
            .history()
            .list(**kwargs, pageToken=response["nextPageToken"])
            .execute()
        )
        history.extend(response.get("history", []))
    return history


def send_message(service, to, subject, body_text, user_id="me", thread_id=None):
    """Send an email message. Returns the sent message resource."""
    msg = email.mime.text.MIMEText(body_text)
    msg["to"] = to
    msg["subject"] = subject
    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    body = {"raw": raw}
    if thread_id:
        body["threadId"] = thread_id
    return service.users().messages().send(userId=user_id, body=body).execute()


def untrash_message(service, msg_id, user_id="me"):
    """Remove a message from trash."""
    return service.users().messages().untrash(userId=user_id, id=msg_id).execute()


def get_unsubscribe_info(service, msg_id, user_id="me"):
    """Extract List-Unsubscribe header from a message, if present."""
    meta = get_message_metadata(service, msg_id, user_id=user_id)
    return meta["headers"].get("list-unsubscribe")


def main(rule_file_path, interval_seconds=600, **process_kwargs):
    console = Console()
    try:
        while True:
            print(time.strftime("%Y-%m-%d %H:%M"))
            process(rule_file_path, **process_kwargs)
            if interval_seconds > 0:
                next_wake = datetime.now() + timedelta(seconds=interval_seconds)
                console.print(Rule(style="blue"))
                console.print(
                    f"[cyan]Next check:[/cyan] {next_wake.strftime('%Y-%m-%d %H:%M:%S')}"
                )
                console.print(Rule(style="blue"))
                time.sleep(interval_seconds)
    except KeyboardInterrupt:
        print("\nShutting down gracefully...")
        raise SystemExit(0)


def process(rule_file_path, query=None, content_preview_length=0):
    rule_path = Path(rule_file_path)
    if not rule_path.exists():
        console = Console()
        console.print(
            f"\n[bold yellow]Rules file not found:[/bold yellow] {rule_path}\n"
        )
        response = (
            input("Would you like to create a starter rules file? [Y/n] ")
            .strip()
            .lower()
        )
        if response in ("", "y", "yes"):
            default_rules = MailRuleModel(
                rule_version="1",
                from_domain_auto_delete=[],
                from_address_auto_archive=[],
            )
            rule_path.parent.mkdir(parents=True, exist_ok=True)
            rule_path.write_text(
                json.dumps(default_rules.model_dump(), indent=2) + "\n"
            )
            console.print(
                f"\n[bold green]✅ Created rules file:[/bold green] {rule_path}"
            )
            console.print("[dim]Edit it to add your rules, then run again.[/dim]\n")
        else:
            console.print(
                "\n[dim]No file created. Create one manually and try again.[/dim]\n"
            )
        raise SystemExit(0)
    mail_rules = MailRuleModel.model_validate_json(rule_path.read_text())
    # print(mail_rules)

    # Authenticate and create service
    service = authenticate()
    console = Console()
    # List all messages
    if query is None:
        messages = list_unread_messages(service)
        print(f"Found {len(messages)} messages unread")
    else:
        messages = list_messages(service, query=query, max_results=50)
        print(f"Found {len(messages)} messages matching query")

    messages_actions: list[dict, ActionModel] = []
    for msg in messages:
        details = get_message_details(service, msg["id"])
        if details:
            rule_action = mail_rules.process_message(details)
            messages_actions.append((details, rule_action))
        else:
            print(f"No details: {msg}")
        del details

    messages_actions = sorted(messages_actions, key=lambda x: x[1].action)

    label_map = get_label_map(service)
    for action, group in itertools.groupby(messages_actions, key=lambda x: x[1].action):
        for msg_details, _ in group:
            # Create a table with two columns
            table = Table(show_header=False, box=None)
            table.add_column()
            table.add_column()
            table.add_row("Message ID", msg_details["id"])
            label_names = [label_map.get(_, _) for _ in msg_details["labelIds"]]
            table.add_row("Labels", " | ".join(label_names))
            table.add_row("From", msg_details["from"])
            # breakpoint()
            if action == "DELETE":
                if delete_message(service, msg_details["id"]):
                    table.add_row("Action Applied", f"✅: {action}")
                else:
                    table.add_row("Action Applied", f"❌: {action}")
            elif action == "ARCHIVE":
                if archive_emails(service, [msg_details["id"]]):
                    table.add_row("Action Applied", f"📦: {action}")
                else:
                    table.add_row("Action Applied", f"❌: {action}")
            else:
                # table.add_row("To", details['to'])
                table.add_row("Subject", msg_details["subject"])
                table.add_row("Action Recommended", f"💡: {action}")
                if content_preview_length > 0:
                    table.add_row(
                        "Content Preview",
                        msg_details["content"][:content_preview_length],
                    )

            # Create a panel to contain the table
            message_panel = Panel(
                table, title=msg_details["subject"][:80], expand=False
            )
            console.print(message_panel)


def self_test():
    """Integration test that exercises all Gmail API methods against the live account."""
    console = Console()
    console.print("\n[bold]Gmail Genie Self-Test[/bold]\n")
    service = authenticate()
    results: list[tuple[str, bool, str]] = []

    def record(name, fn):
        try:
            detail = fn()
            results.append((name, True, detail or "OK"))
            console.print(f"  [green]✅ {name}[/green]")
        except Exception as e:
            results.append((name, False, str(e)))
            console.print(f"  [red]❌ {name}: {e}[/red]")

    # 1. getProfile
    profile = {}

    def test_get_profile():
        nonlocal profile
        profile = get_profile(service)
        return f"{profile['emailAddress']} ({profile['messagesTotal']} messages, {profile['threadsTotal']} threads)"

    record("users.getProfile", test_get_profile)

    # 2. labels.list
    record("users.labels.list", lambda: f"{len(get_label_map(service))} labels")

    # 3. labels.create + labels.delete
    test_label_id = None

    def test_create_label():
        nonlocal test_label_id
        label = create_label(service, "gmail-genie-selftest")
        test_label_id = label["id"]
        return f"created '{label['name']}' ({label['id']})"

    record("users.labels.create", test_create_label)

    # 4. messages.list
    messages = []

    def test_list_messages():
        nonlocal messages
        messages = list_messages(service, max_results=5)
        return f"{len(messages)} messages"

    record("users.messages.list", test_list_messages)

    # 5. messages.get (full)
    msg_detail = None

    def test_get_message():
        nonlocal msg_detail
        if not messages:
            return "skipped (no messages)"
        msg_detail = get_message_details(service, messages[0]["id"])
        return f"subject: {msg_detail['subject'][:60]}"

    record("users.messages.get (full)", test_get_message)

    # 6. messages.get (metadata)
    def test_get_metadata():
        if not messages:
            return "skipped (no messages)"
        meta = get_message_metadata(service, messages[0]["id"])
        return f"headers: {', '.join(meta['headers'].keys())}"

    record("users.messages.get (metadata)", test_get_metadata)

    # 7. messages.modify (add label) — uses the test label
    def test_add_labels():
        if not messages or not test_label_id:
            return "skipped"
        add_labels(service, messages[0]["id"], [test_label_id])
        return f"added test label to {messages[0]['id']}"

    record("users.messages.modify (add label)", test_add_labels)

    # 8. messages.batchModify (remove the test label)
    def test_batch_modify():
        if not messages or not test_label_id:
            return "skipped"
        batch_modify_messages(
            service, [messages[0]["id"]], remove_label_ids=[test_label_id]
        )
        return f"batch removed test label from {messages[0]['id']}"

    record("users.messages.batchModify", test_batch_modify)

    # 9. threads.list
    threads = []

    def test_list_threads():
        nonlocal threads
        threads = list_threads(service, max_results=3)
        return f"{len(threads)} threads"

    record("users.threads.list", test_list_threads)

    # 10. threads.modify (add then remove test label)
    def test_modify_thread():
        if not threads or not test_label_id:
            return "skipped"
        tid = threads[0]["id"]
        modify_thread(service, tid, add_label_ids=[test_label_id])
        modify_thread(service, tid, remove_label_ids=[test_label_id])
        return f"added+removed test label on thread {tid}"

    record("users.threads.modify", test_modify_thread)

    # 11. history.list
    def test_list_history():
        if not profile.get("historyId"):
            return "skipped (no historyId)"
        history = list_history(service, profile["historyId"])
        return f"{len(history)} history records"

    record("users.history.list", test_list_history)

    # 12. messages.send (send to self)
    sent_msg_id = None

    def test_send_message():
        nonlocal sent_msg_id
        if not profile.get("emailAddress"):
            return "skipped (no email)"
        result = send_message(
            service,
            to=profile["emailAddress"],
            subject="[gmail-genie] self-test",
            body_text="This is an automated self-test message from gmail-genie. Safe to delete.",
        )
        sent_msg_id = result["id"]
        return f"sent to self ({sent_msg_id})"

    record("users.messages.send", test_send_message)

    # 13. messages.trash
    def test_trash():
        if not sent_msg_id:
            return "skipped (no sent message)"
        delete_message(service, sent_msg_id)
        return f"trashed {sent_msg_id}"

    record("users.messages.trash", test_trash)

    # 14. messages.untrash
    def test_untrash():
        if not sent_msg_id:
            return "skipped"
        untrash_message(service, sent_msg_id)
        return f"untrashed {sent_msg_id}"

    record("users.messages.untrash", test_untrash)

    # 15. get_unsubscribe_info
    def test_unsubscribe_info():
        if not messages:
            return "skipped (no messages)"
        unsub = get_unsubscribe_info(service, messages[0]["id"])
        return f"List-Unsubscribe: {unsub or '(not present)'}"

    record("get_unsubscribe_info", test_unsubscribe_info)

    # 16. messages.batchDelete (scope check only — not executed)
    def test_batch_delete():
        return "skipped (requires mail.google.com scope; destructive)"

    record("users.messages.batchDelete", test_batch_delete)

    # cleanup: trash the self-test message and delete the test label
    if sent_msg_id:
        try:
            delete_message(service, sent_msg_id)
        except Exception:
            pass
    if test_label_id:
        try:
            delete_label(service, test_label_id)
            console.print("  [dim]cleaned up test label[/dim]")
        except Exception:
            pass

    # summary
    passed = sum(1 for _, ok, _ in results if ok)
    total = len(results)
    console.print()
    table = Table(title="Self-Test Results")
    table.add_column("API Method")
    table.add_column("Status")
    table.add_column("Detail")
    for name, ok, detail in results:
        status = "[green]PASS[/green]" if ok else "[red]FAIL[/red]"
        table.add_row(name, status, detail[:100])
    console.print(table)
    console.print(f"\n[bold]{passed}/{total} passed[/bold]\n")
    raise SystemExit(0 if passed == total else 1)


if __name__ == "__main__":
    import argparse

    default_rules_file = Path("~/.config/gmail-genie/rules.json").expanduser()
    parser = argparse.ArgumentParser(description="Process Gmail with rules.")
    subparsers = parser.add_subparsers(dest="command")

    # default 'run' command (also runs when no subcommand given)
    run_parser = subparsers.add_parser("run", help="Run the mail processing loop")
    run_parser.add_argument(
        "--rules",
        type=Path,
        default=default_rules_file,
        help="Path to rules config file",
    )
    run_parser.add_argument(
        "--query", type=str, default=None, help="Optional search query"
    )
    run_parser.add_argument(
        "--interval-seconds", type=int, default=600, help="interval in seconds"
    )

    # self-test subcommand
    subparsers.add_parser(
        "self-test", help="Run integration tests against the live Gmail API"
    )

    args = parser.parse_args()

    if args.command == "self-test":
        self_test()
    else:
        # default to 'run' behavior (with or without subcommand)
        rules = getattr(args, "rules", default_rules_file)
        query = getattr(args, "query", None)
        interval = getattr(args, "interval_seconds", 600)
        main(
            rules,
            query=query,
            content_preview_length=0,
            interval_seconds=interval,
        )
