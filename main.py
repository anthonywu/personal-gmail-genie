import functools
import itertools
import os
import time
import pickle
from pathlib import Path
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
import base64

from rich.console import Console
from rich.table import Table
from rich.panel import Panel


from pydantic import BaseModel
from typing import Literal


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

    # Load credentials from token.pickle if it exists
    if os.path.exists("token.pickle"):
        with open("token.pickle", "rb") as token:
            creds = pickle.load(token)

    # If credentials are invalid or don't exist, get new ones
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file("credentials.json", SCOPES)
            creds = flow.run_local_server(port=0)

        # Save credentials for future use
        with open("token.pickle", "wb") as token:
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


def main(rule_file_path, interval_seconds=600, **process_kwargs):
    while True:
        process(rule_file_path, **process_kwargs)
        time.sleep(interval_seconds)


def process(rule_file_path, query=None, content_preview_length=0):
    mail_rules = MailRuleModel.parse_file(rule_file_path)
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


if __name__ == "__main__":
    import argparse

    default_rules_file = Path("~/.config/gmail-genie/my_rules.json").expanduser()
    parser = argparse.ArgumentParser(description="Process Gmail with rules.")
    parser.add_argument(
        "--rules",
        type=Path,
        default=default_rules_file,
        help="Path to rules config file",
    )
    parser.add_argument("--query", type=str, default=None, help="Optional search query")
    parser.add_argument(
        "--interval-seconds", type=int, default=600, help="interval in seconds"
    )
    args = parser.parse_args()
    main(
        args.rules,
        query=args.query,
        content_preview_length=0,
        interval_seconds=args.interval_seconds,
    )
