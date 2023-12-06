#!/usr/local/bin/python3
# given a filename (output of Amazon Comprehend), analyze common, uncommon and unique entities and output to new file

import json, sys, re

DEBUG = 0
filename = sys.argv[1] if len(sys.argv) > 1 else 'output.json' 

def entity_cleanup( label ): # normalize entities- convert to lowercase & condense whitespace
	return re.sub(r'\s+',' ',label.lower().replace('=\n','').replace('=3D','=').translate({ord(chr): None for chr in '\n\'"'}) )

# Go through all the entities and find ones common/uncommon among the user list
def get_topic_buckets( entity_list, user_count ):
	topic_buckets = { '>75%': {},'<25%': {},'<10%': {}, '1': {} }
	for entity, entity_stats in entity_list.items():
		referenced_by_count = len(entity_stats['users'])
		add_to_bucket = None
		if referenced_by_count == 1:
			add_to_bucket = '1'
		elif referenced_by_count/user_count >= 0.75:
			add_to_bucket = '>75%'
		elif referenced_by_count/user_count <= 0.1:
			add_to_bucket = '<10%'
		elif referenced_by_count/user_count <= 0.25:
			add_to_bucket = '<25%'
		
		if add_to_bucket:
			topic_buckets[add_to_bucket][entity] = entity_stats
			
	return topic_buckets

# Output the top N topics from the common/uncommon lists
def dump_topic_buckets( user_list, buckets, output_filename, count ):
	stop = 0 - count
	cols = ['bucket','entity','referenced']
	cols.extend( user_list )
	with open(output_filename, 'w') as user_file:
		user_file.write('\t'.join(cols) + '\n')
		for bucket, bucket_items in buckets.items():
			# print('Bucket: ',bucket)	
			for entity in sorted(bucket_items.items(), key=lambda x:x[1]['count'])[:stop:-1]:
				entity_usage = [ bucket, entity[0], str(entity[1]['count']) ]
				entity_usage.extend([ str(entity[1]['users'][user]) if user in entity[1]['users'] else '0' for user in user_list ])
				user_file.write('\t'.join(entity_usage) + '\n')
				# print('  ',entity[0],' -> ',entity[1]['count'])

# Output the top 100 unique topics per user [topics not mentioned by other users]
def top_unique_topics_by_user( user_list, buckets, output_filename, count):
	top_unique_topics = {user: [] for user in user_list}
	for entity in sorted(buckets['1'].items(), key=lambda x:x[1]['count'])[::-1]:
		this_user = list(entity[1]['users'].keys())[0]  # we are going through the list of topics referenced by only 1 user, so take first
		top_unique_topics[ this_user ].append( entity[0] + ' (' + str(entity[1]['count']) + ')' )
	
	with open(output_filename, 'w') as user_file:
		user_file.write('\t'.join(user_list) + '\n')
		for top_count in range(count):
			user_file.write( 
				'\t'.join([top_unique_topics[user][top_count] if top_count < len(top_unique_topics[user]) else '' for user in user_list]) + '\n' 
			)
			
# Output the top 100 topics per user [may overlap topics by other users, not the same as top topics overall]
def top_topics_by_user( user_topics, output_filename, count):
	user_list = list(user_topics.keys())
	top_topics = {user: [item[0] + ' (' + str(item[1]) + ')' for item in list(reversed(sorted(user_topics[user].items(), key=lambda x:x[1])))] for user in user_list}
	with open(output_filename, 'w') as user_file:
		user_file.write('\t'.join(user_list) + '\n')
		for top_count in range(count):
			user_file.write( 
				'\t'.join([top_topics[user][top_count] if top_count < len(top_topics[user]) else '' for user in user_list]) + '\n' 
			)


# Import NLP analysis from Amazon Comprehend into dictionary structures
entities_by_user = {}
all_entities = {}
with open(filename) as user_file:
	for file_analysis in user_file:
		parsed     = json.loads(file_analysis)
		print('Importing analysis of',parsed['File'],'...')
		email_user = re.match(r'^(.*)-(in|out)-\d\d.txt',parsed['File']).group(1) # assumes original files were named 'username...-in-xx.txt'
		print('Identified user: [',email_user,"]")
		entities   = parsed['Entities' if 'Entities' in parsed else 'KeyPhrases']
		for entity in entities:
			if 'Type' not in entity or entity['Type'] in ['COMMERCIAL_ITEM','ORGANIZATION','LOCATION']: # 'PERSON'
				entity_name = entity_cleanup(entity['Text'])
				
				if email_user not in entities_by_user:
					entities_by_user[ email_user ] = {}
				if entity_name not in entities_by_user[ email_user ]:
					entities_by_user[ email_user ][ entity_name ] = 0
				if entity_name not in all_entities:
					all_entities[ entity_name ] = { 'count': 0, 'users': {} }
				if email_user not in all_entities[ entity_name ]['users']:
					all_entities[ entity_name ]['users'][ email_user ] = 0
				
				entities_by_user[ email_user ][ entity_name ]       += 1
				all_entities[ entity_name ]['users'][ email_user ]  += 1
				all_entities[ entity_name ]['count']                += 1
		if DEBUG:
			break


topic_buckets = get_topic_buckets( all_entities, len(entities_by_user) )
dump_topic_buckets( list(entities_by_user.keys()), topic_buckets, filename.replace('.json','-topic-freq.tsv'), 100 )
top_unique_topics_by_user( list(entities_by_user.keys()), topic_buckets, filename.replace('.json','-topic-unique.tsv'), 100 )
top_topics_by_user( entities_by_user, filename.replace('.json','-topic-top100.tsv'), 100 )
