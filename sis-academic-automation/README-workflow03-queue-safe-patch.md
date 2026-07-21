# Workflow 03 queue-safe negative validation repair

The duplicate-student acceptance test correctly detected the duplicate, but
the Code node threw an uncaught exception. That stopped the workflow before
the Automation Queue row could be marked failed.

This patch changes `Build File Marks Request` so deterministic spreadsheet
validation problems return a structured failed queue outcome. The failed
branch then reaches `Update File Automation Queue`, while the Supabase marks
RPC is not called.

Apply the repository patch, copy the corrected Code-node source to the
clipboard, replace the complete contents of the n8n node, save and publish.
A new Google Form response is required because the original row-added event
has already occurred.
