We have found that operator ServiceAccounts have an owner ref to the CSV.  That means when a CSV is deleted the SA is deleted.  This makes opeartors unhappy.

Full context (it's a long thread): https://coreos.slack.com/archives/CCRND57FW/p1607684271250500

TL;DR:
1. make sure SA exists
2. make sure SA does _not_ have an owner reference

The SSS are broke into 2 so that when we delete the SA SSS it does _not_ delete the SA's!  This is critical...
