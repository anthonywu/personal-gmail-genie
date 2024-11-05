# personal gmail genie

the beginnings of a Gmail AI assistant, for everyone's personal use

Goal: give Gmail users personal agency, security, and privacy to add agentic assistants to their email


## Usage

### One time setup

This step is really annoying, you need to get the `credentials.json` file and save it where you plan to run the python script below.

Just go to ChatGPT or Claude and ask for a walkthrough of "Where can I get the Gmail API credentials.json from the Google Cloud Console". This guide does not help with the shit UX that Google put up in front of the Gmail developer experience.


### Running the script

For now, this is not a `pip install`-able package. Just do this:

1. `brew install uv`
2. `uv venv` && `source .venv/bin/activate`
3. `uv pip install -r requirements.txt`
4. `python main.py <path to your rules.json> [optional: gmail search query]`  # default to list of your unread emails

## progress

- list emails by query
- working demo of basic archive / delete actions
- mapping label internal id (e.g. `LABEL_11`) <-> humanized label names (e.g. `Finance`)

## todo

- improve the rules schema
- proper commandline `argparser` setup
- via "LLM Tool Use", connect to Ollama or Apple-MLX local LLM models for:
  - summarization
  - suggested auto-reply
  - auto-forward to exec assistants
  - auto-forward to another person (family, co-worker)
  - auto sort/delete and self-(learn+suggest) new rules over time
  - etc AI-enabled features
- GUI for configs
- Background daemon to run this continuously on your Mac
  - menu bar daemon?
  - just do its thing and send you a system notification?
- History server
  - store history of agent actions

## questions

- should this run in the Cloud? You'd give up some privacy

## related projects

- many related attempts on PyPi and GitHub throughout the years, but none/few was built with 2024 LLM capabilities in mind
