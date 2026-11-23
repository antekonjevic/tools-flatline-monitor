# Flatline

Flatline keeps watch over your websites and shows, at a glance, which ones are up and which are down. It covers availability only, with no analytics, incident reports or team features. It's free, you run your own copy, and it does one job.

- An overview of every website: status, how long it's been that way, 90 days of daily bars and uptime
- Six months of history per website: when it went down, for how long and why
- A secret, read-only board link to open on a phone or leave on a spare screen
- Import and export of every website's settings as a JSON file
- Down only when it's sure: failures are ignored when Flatline's own connection is the problem

Built with Rails 8.1, SQLite and Solid Queue. No Node and no build step.

## Contents

- [Run your own Flatline](#run-your-own-flatline)
- [How deploys work](#how-deploys-work)
- [Resetting the password](#resetting-the-password)
- [Rolling back](#rolling-back)
- [Configuration](#configuration)
- [How checks work](#how-checks-work)
- [Importing and exporting websites](#importing-and-exporting-websites)
- [Development](#development)

## Run your own Flatline

You need a GitHub account, a fresh **Ubuntu 24.04** server you can reach over SSH, and a (sub)domain whose DNS you control. It takes about 20 minutes, most of it the install compiling Ruby. Every push to your fork's `main` then deploys to your server.

### 1. Fork this repo and turn on Actions

Fork the repository on GitHub and keep the fork **public**: the server downloads each release straight from GitHub, without credentials. GitHub turns Actions off on new forks, so open your fork's **Actions** tab and enable workflows.

### 2. Point DNS at the server

Create an `A` record for your subdomain, for example `status.example.com`, pointing at the server's IPv4 address. Add an `AAAA` record too if the server has IPv6. Caddy needs these to get an HTTPS certificate from Let's Encrypt. If your domain has `CAA` records, one of them must allow `letsencrypt.org`.

### 3. Log in to the server with an SSH key

The install turns off password logins, but only when it finds an SSH key for your user (or root), so you can't lock yourself out.

### 4. Create a deploy key on your own computer

GitHub Actions uses this key to reach the server:

```sh
ssh-keygen -t ed25519 -f flatline_deploy -N "" -C "flatline deploy"
```

You'll paste the public half (`flatline_deploy.pub`) into the install, and the private half (`flatline_deploy`) into GitHub.

### 5. Install on the server

```sh
git clone https://github.com/<you>/flatline.git
cd flatline
sudo bin/install
```

It asks for:

| Prompt | Answer |
|---|---|
| Domain | Only the host name, for example `status.example.com` (no `https://`) |
| Time zone | For showing times and counting days, for example `Europe/Amsterdam` |
| Owner password | At least 12 characters; only a hash of it is stored |
| Deploy key | The contents of `flatline_deploy.pub` |

Then it installs system packages, [Caddy](https://caddyserver.com) and Ruby (through [mise](https://mise.jdx.dev)); creates a `deploy` user; writes the configuration file, the Caddy config and two systemd services (`flatline-web` and `flatline-jobs`); deploys the current commit; and lets only SSH, HTTP and HTTPS through the firewall, turns off SSH passwords and turns on automatic security updates. If something fails, fix it and run it again: it only asks for what's missing.

### 6. Add the deploy secrets to your fork

When it finishes, the install prints four values. Add each one in your fork under *Settings → Secrets and variables → Actions → New repository secret*:

| Secret | Value |
|---|---|
| `DEPLOY_HOST` | Your domain, for example `status.example.com` |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_KNOWN_HOSTS` | The server's host key line as printed, for example `status.example.com ssh-ed25519 AAAA…` |
| `DEPLOY_SSH_KEY` | The private key: the whole contents of `flatline_deploy` |

### 7. Check it

Open `https://status.example.com` and sign in. To try a deploy from GitHub without a new commit, open the latest **CI** run on `main` in your fork's Actions tab and choose **Re-run all jobs**; the deploy step ends with `Deployed <commit>`. From now on, every push to `main` deploys.

Files on the server:

```
/home/deploy/flatline/
  releases/<timestamp>/   the last 5 deploys
  current -> releases/…   the live release
  shared/storage/         SQLite database files
  shared/flatline.env     configuration and secrets
```

Logs go to the system journal: `journalctl -u flatline-web -u flatline-jobs -f`.

## How deploys work

Every push to `main` runs the tests, RuboCop, Brakeman and the dependency audits. If they pass, GitHub Actions connects to the server over SSH as the `deploy` user and runs `bin/deploy` for that commit. It fetches the commit into a new release folder, links the shared storage and configuration into it, installs gems, precompiles assets, migrates the databases, switches `current` to it and restarts both services. The worker finishes the checks it's running before it stops.

Only one deploy runs at a time. If a step fails before the switch, the live release isn't touched; if the new release doesn't answer within 30 seconds, `current` goes back to the previous one.

Without the secrets, the deploy step is skipped, so pull requests and forks without a server still get CI. On a public repo anyone can read the Actions logs; they contain no secrets, and GitHub masks the secret values.

## Resetting the password

There's one owner password, and it lives only in the configuration file. On the server:

```sh
sudo -iu deploy
cd ~/flatline/current && RAILS_ENV=production mise exec -- bin/rails flatline:password
```

Put the line it prints into `~/flatline/shared/flatline.env`, replacing the old `FLATLINE_PASSWORD_DIGEST` line, then restart:

```sh
sudo systemctl restart flatline-web flatline-jobs
```

Changing the password signs out every existing session.

## Rolling back

On the server, as the deploy user:

```sh
~/flatline/current/bin/rollback
```

This points `current` at the previous release and restarts both services. Database migrations are not undone. The last five releases are kept, so you can go back up to four times.

## Configuration

All settings live in `/home/deploy/flatline/shared/flatline.env`, which is never committed:

| Variable | Purpose |
|---|---|
| `FLATLINE_HOST` | The (sub)domain Flatline runs on |
| `FLATLINE_PASSWORD_DIGEST` | A hash of the owner's password, from `bin/rails flatline:password` |
| `SECRET_KEY_BASE` | Rails' secret key, generated during install |
| `FLATLINE_TIME_ZONE` | Time zone for showing times and counting days, e.g. `Europe/Amsterdam` (UTC by default) |
| `FLATLINE_REPOSITORY_URL` | Optional. The repo linked from the `User-Agent` that checks send, so website owners can see what's visiting them. Set it to your fork's URL if you've changed how Flatline behaves; it defaults to the original repo. |

Restart both services after changing it: `sudo systemctl restart flatline-web flatline-jobs`.

## How checks work

- Every minute, a Solid Queue job queues every website that's due. Websites are checked every 1, 5, 15 or 60 minutes.
- A check is an HTTP `GET` that follows up to 5 redirects and gives up after 30 seconds. It sends a `User-Agent` that names Flatline and links to this repo.
- **Down:** DNS failure, refused or reset connection, timeout, invalid or expired certificate, HTTP status 400 or above, or the required text missing from the page. A website counts as down after a set number of failed checks in a row (2 by default). After a failed check, Flatline checks again one minute later.
- **Warning:** the website took more than 5 seconds, or its certificate expires within 14 days.
- **Paused:** not checked; paused time doesn't count against uptime.
- **Connection guard:** before a failure counts, Flatline contacts Cloudflare and Google. If it can reach neither, the failure is ignored and the overview and board say Flatline is offline.
- Checks interrupted by a deploy or restart are thrown away, not counted as failures.
- The overview and board always say when the last check ran, and warn if checking has stopped.
- Every result is kept for 6 months, then deleted by a nightly job. Daily summaries keep the 90-day bars and uptime fast.

## Importing and exporting websites

Under **Import & export** in the admin area you can download every website's settings as a JSON file, and import such a file. Use it as a backup, to move to another server, or to add many websites at once.

```json
{
  "flatline": 1,
  "websites": [
    {
      "name": "Acme shop",
      "url": "https://shop.example.com",
      "group": "Acme",
      "interval_minutes": 5,
      "required_text": "Add to cart",
      "failures_before_down": 2,
      "paused": false
    }
  ]
}
```

- Websites are matched by `url`. Ones already in Flatline get the file's settings; new ones are added and checked straight away.
- Websites that aren't in the file are left alone. Importing never removes anything.
- Only `name` and `url` are needed for a new website. A key that's left out keeps its current value (or the default); `null` clears `group` or `required_text`.
- If any entry is invalid, nothing is imported, and the page lists what to fix.
- History, uptime and the board link aren't part of the file.

## Development

You need Ruby (see `.ruby-version`) and SQLite.

```sh
bin/setup     # installs gems, prepares the databases and starts the app
bin/dev       # starts the app with the check worker inside it
```

Open http://localhost:3000 and sign in with the password `flatline`, which works only in development when `FLATLINE_PASSWORD_DIGEST` isn't set.

```sh
bin/rails test     # tests
bin/rubocop        # style
bin/brakeman       # security scan
bin/ci             # everything CI runs
```

## License

[MIT](LICENSE)
