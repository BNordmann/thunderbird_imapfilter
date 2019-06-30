---------------
--    Reqs   --
---------------

tb = require("tb_filter")

---------------
--  Options  --
---------------

options.timeout = 120
options.subscribe = true
options.info = true
options.keepalive = 29

----------------
--  Accounts  --
----------------

-- Connects to "imap1.mail.server", as user "user1" with "secret1" as
-- password.
account1 = IMAP {
    server = 'imap1.mail.server',
    username = 'user1',
    password = 'secret1',
    port = 993,
    ssl = 'tls1',
}

mbox = account1["INBOX"]
msgs = mbox:select_all()
tb.do_thunderbird_filter(account1, msgs, "msgFilterRules.dat")
