View Salesforce Files of Related Records
========================================

Coming soon!

This only works when the ContentVersion.FirstPublishLocationId is a child entity of the parent entity you want to share to.
For example, when uploading a file to a contact record.

Must go through the Files Related List because that will set the ContentVersion.FirstPublishLocationId to that record id.
If you post a file via Chatter Feed then the ContentVersion.FirstPublishLocationId is set to the current user id. Unless the file is uploaded in a manner we can definitively know was uploaded to a child record and that our logic
shared it to the parent record then we have no way of being able to unshare the file from the parent record later.
It would be ambiguous whether our logic shared the file to the parent or another user did it explicitly.

Trigger then stamps a custom field on the ContentVersion to indicate it was shared automatically from the child record
so that when the child record is re-parented then we know to unshare automatically the file from the parent and share it to the new parent.
