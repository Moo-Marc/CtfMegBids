# CtfMegBids
Matlab code for converting and managing CTF MEG recordings into BIDS

Marc Lalancette, Montreal Neurological Institute-Hospital, McGill University

# Usage
Runs on raw CTF MEG acquisition folders and moves all datasets (.ds) and
optional adjoining files (.pos, .log, .jpg) into a specified BIDS directory, or
into the parent folder ("/CTF-acquisition" in the following example):
`MegToBids('/CTF-acquisition/20250101');`

See MegToBids.m for further usage documentation.

Can run from the operating system command line, e.g.:
matlab -batch "MegToBids('/CTF-acquisition/20250101');"

