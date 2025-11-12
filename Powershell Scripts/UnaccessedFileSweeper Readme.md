V.2.0

✅ New Features:
✔ Resume Capability: Tracks processed files in $StateFile. If interrupted, resume from where you left off.
✔ Real-Time Dashboard: Displays processed count, speed (files/sec), and ETA dynamically.
✔ Chunking + Runspaces for massive scale.
✔ Empty Folder Cleanup after file operations.
✔ Dry-Run, Logging, and Summary retained.

⚠ Performance Tips:

Tune $MaxThreads and $ChunkSize for your hardware.
For billions of files, split top-level directories and run multiple instances in parallel.
Use SSD/NVMe and separate disk for logs.

V.2.1
✅ New Features:
✔ Email Notification using Send-MailMessage (configure SMTP).
✔ Microsoft Teams Notification using Incoming Webhook (requires Teams connector URL).
✔ All previous features: Runspaces, Chunking, Resume, Dashboard with ETA, Empty Folder Cleanup, Dry-Run, Logging, Summary.

⚠ Setup Notes:

Replace smtp.yourcompany.com and email addresses with your SMTP details.
For Teams, create an Incoming Webhook in your Teams channel and use its URL.
Ensure PowerShell has access to the internet for Teams webhook.