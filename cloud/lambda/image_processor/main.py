import json
import boto3
import urllib.parse
import os

s3 = boto3.client('s3')
sqs = boto3.client('sqs')

SQS_QUEUE_URL = os.environ.get('SQS_QUEUE_URL')

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    
    for record in event.get('Records', []):
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        # Processiamo solo le immagini RAW
        if not key.startswith('images/raw/'):
            print(f"Ignorato {key} (non in images/raw/)")
            continue
            
        print(f"Inizio elaborazione immagine: {key} dal bucket {bucket}")
        
        # Otteniamo l'oggetto S3 per leggerne i metadati inseriti dal backend FastAPI
        try:
            response = s3.get_object(Bucket=bucket, Key=key)
            metadata = response.get('Metadata', {})
        except Exception as e:
            print(f"Errore nella lettura da S3: {e}")
            continue
        
        job_id = metadata.get('job_id', key.split('/')[-1].split('.')[0])
        training_set = metadata.get('training_set', 'fullset')
        architecture = metadata.get('architecture', 'gcn_sage')
        vector_db_size = metadata.get('vector_db_size', 'subset')
        
        # --- IMAGE PROCESSING ---
        # Qui potremmo usare la libreria PIL per ridimensionare l'immagine e alleggerirla.
        # Per ora spostiamo l'immagine ottimizzata nella cartella finale per il worker.
        optimized_key = f"images/optimized/{job_id}.jpg"
        
        try:
            s3.copy_object(
                Bucket=bucket,
                CopySource={'Bucket': bucket, 'Key': key},
                Key=optimized_key,
                Metadata=metadata,
                MetadataDirective='REPLACE'
            )
            print(f"Immagine elaborata e salvata in {optimized_key}")
            
            # Opzionale: cancelliamo l'immagine originale RAW per pulizia
            s3.delete_object(Bucket=bucket, Key=key)
            
        except Exception as e:
            print(f"Errore nell'ottimizzazione e spostamento immagine: {e}")
            continue
        
        # --- JOB QUEUEING ---
        # Creiamo il payload esatto che si aspetta l'AI Worker in Kubernetes
        job_message = {
            "job_id": job_id,
            "type": "custom",
            "training_set": training_set,
            "architecture": architecture,
            "vector_db_size": vector_db_size,
            "image_key": optimized_key
        }
        
        try:
            sqs.send_message(
                QueueUrl=SQS_QUEUE_URL,
                MessageBody=json.dumps(job_message)
            )
            print(f"Job {job_id} accodato con successo in SQS!")
        except Exception as e:
            print(f"Errore nell'invio del messaggio a SQS: {e}")
            
    return {
        'statusCode': 200,
        'body': json.dumps('Elaborazione completata')
    }
