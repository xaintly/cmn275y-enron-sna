# cmn275y-enron-sna
Scripts used to analyze the Enron Corpus

Corpus can be downloaded from CMU at https://www.cs.cmu.edu/~enron/

# edgefinder.pl
This script runs through the 'maildir/' and outputs a .csv file of 
  source,target,count
indicating the number of times each person at enron sent an email to a each other person

# maildumper.pl
Given a pattern like "kenneth.lay", dumps out the message body of all emails to and from that person

# view_json.py
Given a file output of entities or key phrases from Amazon Comprehend, creates several derivative files of unique and common topics by the people mentioned.
Assumes that filenames given to Comprehend were in the naming format email.address-xx where xx is some number (email bodies are chunked into files of size 1,048,000 bytes per Comprehend's max file size)
