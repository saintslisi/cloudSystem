import os, uuid, json, logging
from dotenv import load_dotenv
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, BackgroundTasks
from sqlmodel import SQLModel, Field, Session, create_engine
import pika
from redis import Redis
from typing import Optional
from fastapi.staticfiles import StaticFiles


load_dotenv()
POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DB = os.getenv("POSTGRES_DB")
POSTGRES_HOST = os.getenv("POSTGRES_HOST")
POSTGRES_PORT = os.getenv("POSTGRES_PORT")

DATABASE_URL = f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST")
REDIS_HOST = os.getenv("REDIS_HOST")
REDIS_PORT = os.getenv("REDIS_PORT")

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from fastapi.responses import FileResponse

def get_data_dir() -> str:
    env_dir = os.getenv("PROJECT_DATA_DIR")
    if env_dir and os.path.exists(env_dir):
        return env_dir
    if os.path.exists("/app/data"):
        return "/app/data"
    # Fallback to local 'data'
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")

DATA_DIR = get_data_dir()

os.makedirs(os.path.join(DATA_DIR, "images", "imagesTest"), exist_ok=True)
os.makedirs(os.path.join(DATA_DIR, "images", "imageVectorDB"), exist_ok=True)

@app.get("/static/vectorDB/{filename}")
def get_vector_db_image(filename: str):
    try:
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': S3_BUCKET, 'Key': f'images/fullset/VectorDB/{filename}'},
            ExpiresIn=3600
        )
        return RedirectResponse(presigned_url)
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Image {filename} not found in S3")

@app.get("/static/test_images/{filename}")
def get_test_image(filename: str):
    # Prima controlla se è un'immagine custom caricata dall'utente localmente in /tmp
    custom_path = "/tmp/local_custom_images/" + filename
    if os.path.exists(custom_path):
        return FileResponse(custom_path)
        
    try:
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': S3_BUCKET, 'Key': f'images/fullset/Test/{filename}'},
            ExpiresIn=3600
        )
        return RedirectResponse(presigned_url)
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Image {filename} not found in S3")

@app.get("/static/inference/{filename}")
def get_inference_image(filename: str):
    candidate_paths = [
        "/tmp/local_inference_images/" + filename,
        os.path.join(DATA_DIR, "images", "inference", filename),
    ]
    for path in candidate_paths:
        if os.path.exists(path):
            return FileResponse(path)
    raise HTTPException(status_code=404, detail=f"Image {filename} not found")

@app.get("/api/v1/graph/{image_id}")
def get_graph(image_id: str):
    # Prova a leggere da Redis prima (per evitare problemi di FUSE/NTFS)
    try:
        r = get_redis_client()
        if r:
            graph_data = r.get(f"graph_json:{image_id}")
            if graph_data:
                return json.loads(graph_data)
    except Exception as e:
        logging.warning(f"Errore lettura JSON da Redis per {image_id}: {e}")

    # Fallback su file
    candidate_paths = [
        os.path.join(DATA_DIR, "sceneGraph", "json", "inference", f"{image_id}.json"),
        os.path.join(DATA_DIR, "sceneGraph", "json", "fullset", f"{image_id}.json"),
        os.path.join(DATA_DIR, "sceneGraph", "json", "subset", f"{image_id}.json")
    ]
    for path in candidate_paths:
        if os.path.exists(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                logging.warning(f"Errore lettura file {path}: {e}")
                
    raise HTTPException(status_code=404, detail=f"Graph JSON non trovato per {image_id}.")

@app.get("/api/v1/job/{job_id}/graph")
def get_job_graph(job_id: str):
    """
    Ritorna il JSON del grafo generato per un determinato job o immagine di test.
    """
    # Prova a leggere da Redis prima (per evitare problemi di FUSE/NTFS)
    try:
        r = get_redis_client()
        if r:
            graph_data = r.get(f"graph_json:{job_id}")
            if graph_data:
                return json.loads(graph_data)
    except Exception as e:
        logging.warning(f"Errore lettura JSON da Redis per {job_id}: {e}")

    # Fallback su file
    candidate_paths = [
        os.path.join(DATA_DIR, "sceneGraph", "json", "inference", f"{job_id}.json"),
        os.path.join(DATA_DIR, "sceneGraph", "json", "fullset", f"{job_id}.json"),
        os.path.join(DATA_DIR, "sceneGraph", "json", "subset", f"{job_id}.json"),
        os.path.join(DATA_DIR, "sceneGraph", "json", "imagesTest", f"{job_id}.json")
    ]
    
    for path in candidate_paths:
        if os.path.exists(path):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Error reading graph file: {e}")
                
    raise HTTPException(status_code=404, detail="Graph not found for the given job/image ID")

class TestImage(SQLModel, table=True):
    id: str = Field(primary_key=True)
    name: str
    filename: str

class CustomTestImage(SQLModel, table=True):
    id: str = Field(primary_key=True) # it will be the job_id
    name: str
    filename: str # the saved image filename

class Job(SQLModel, table=True):
    job_id: str = Field(default_factory=lambda: str(uuid.uuid4()), primary_key=True)
    status: str = Field(default="PROCESSING")
    result: Optional[str] = Field(default=None,nullable=True)

class CachedSearch(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    image_id: str = Field(index=True)
    training_set: str = Field(index=True)
    architecture: str = Field(index=True)
    vector_db_size: str = Field(index=True)
    result_json: str
engine = create_engine(DATABASE_URL)

@app.on_event("startup")
def init_db():
    try:        
        SQLModel.metadata.create_all(engine)
        
        # Inizializziamo dei dati finti per testare il frontend
        db = Session(engine)
        if db.query(TestImage).count() == 0:
            images_to_insert = []
            subset_dir = os.path.join(DATA_DIR, "images", "subset", "imagesTest")
            fullset_dir = os.path.join(DATA_DIR, "images", "fullset", "Test")
            
            # 1. Carica le prime 25 immagini dal subset
            if os.path.exists(subset_dir) and os.path.isdir(subset_dir):
                files = sorted([f for f in os.listdir(subset_dir) if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
                for f in files[:25]:
                    img_id = os.path.splitext(f)[0]
                    images_to_insert.append(TestImage(id=img_id, name=f"Subset {img_id}", filename=f))
            
            # 2. Carica le prime 25 immagini dal fullset (evitando ID duplicati se presenti)
            if os.path.exists(fullset_dir) and os.path.isdir(fullset_dir):
                files = sorted([f for f in os.listdir(fullset_dir) if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
                inserted = 0
                for f in files:
                    img_id = os.path.splitext(f)[0]
                    if not any(x.id == img_id for x in images_to_insert):
                        images_to_insert.append(TestImage(id=img_id, name=f"Fullset {img_id}", filename=f))
                        inserted += 1
                        if inserted >= 25:
                            break
                            
            # Fallback se entrambe le cartelle falliscono, controlla cartella generica imagesTest
            if not images_to_insert:
                fallback_dir = os.path.join(DATA_DIR, "images", "imagesTest")
                if os.path.exists(fallback_dir) and os.path.isdir(fallback_dir):
                    files = sorted([f for f in os.listdir(fallback_dir) if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
                    for f in files[:50]:
                        img_id = os.path.splitext(f)[0]
                        images_to_insert.append(TestImage(id=img_id, name=f"Test {img_id}", filename=f))
            
            if images_to_insert:
                db.add_all(images_to_insert)
                db.commit()
                logging.info(f"{len(images_to_insert)} Immagini di test inserite con successo nel database Postgres!")
            else:
                logging.warning("Nessuna immagine trovata per inizializzare il DB.")
        db.close()
    except Exception as e:
        logging.error(f"Errore init DB: {str(e)}")

def get_redis_client():
    try:
        r = Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
        return r
    except Exception as e:
        logging.error(f"Errore connessione Redis: {str(e)}")
        return None

@app.get("/api/v1/test-images")
def get_test_images():
    db = Session(engine)
    images = db.query(TestImage).all()
    db.close()
    return images

@app.get("/api/v1/cache-status")
def get_cache_status(training_set: str, architecture: str, vector_db_size: str):
    r = get_redis_client()
    redis_cached = set()
    if r:
        cache_set_key = f"cached_images:{training_set}:{architecture}:{vector_db_size}"
        cached = r.smembers(cache_set_key)
        if cached:
            redis_cached = set(cached)

    db = Session(engine)
    cached_searches = db.query(CachedSearch).filter(
        CachedSearch.training_set == training_set,
        CachedSearch.architecture == architecture,
        CachedSearch.vector_db_size == vector_db_size
    ).all()
    pg_cached = set([c.image_id for c in cached_searches])
    db.close()
    
    all_ids = redis_cached.union(pg_cached)
    result = {}
    for img_id in all_ids:
        result[img_id] = {
            "redis": img_id in redis_cached,
            "postgres": img_id in pg_cached
        }
            
    return result

@app.get("/api/v1/custom-test-images")
def get_custom_test_images():
    db = Session(engine)
    images = db.query(CustomTestImage).all()
    db.close()
    return images

@app.delete("/api/v1/custom-test-images/{image_id}")
def delete_custom_test_image(image_id: str):
    db = Session(engine)
    img = db.query(CustomTestImage).filter(CustomTestImage.id == image_id).first()
    if not img:
        db.close()
        raise HTTPException(status_code=404, detail="Immagine custom non trovata")
    
    # Rimuovi file associato se esiste
    custom_dir = "/tmp/local_custom_images"
    if img.filename:
        file_path = os.path.join(custom_dir, img.filename)
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
            except Exception as e:
                logging.error(f"Errore rimozione file immagine custom {file_path}: {e}")
                
    db.delete(img)
    db.commit()
    db.close()
    return {"message": "Immagine custom rimossa con successo"}

@app.post("/api/v1/save-custom-image/{job_id}")
def save_custom_image(job_id: str):
    db = Session(engine)
    # Controlla se esiste già
    existing = db.query(CustomTestImage).filter(CustomTestImage.id == job_id).first()
    if existing:
        db.close()
        return {"message": "Immagine già salvata nel sistema"}

    # Cerca il file immagine salvato durante l'inferenza
    inference_dir = "/tmp/local_inference_images"
    filename = None
    if os.path.exists(inference_dir):
        for f in os.listdir(inference_dir):
            if f.startswith(job_id) and f.lower().endswith(('.png', '.jpg', '.jpeg')):
                filename = f
                break
    
    if not filename:
        db.close()
        raise HTTPException(status_code=404, detail="Immagine originale dell'inferenza non trovata")

    custom_dir = "/tmp/local_custom_images"
    os.makedirs(custom_dir, exist_ok=True)
    import shutil
    shutil.copy(os.path.join(inference_dir, filename), os.path.join(custom_dir, filename))

    custom_img = CustomTestImage(id=job_id, name=f"Custom {job_id[:6]}", filename=filename)
    db.add(custom_img)
    db.commit()
    db.close()
    return {"message": "Immagine custom salvata con successo"}

AWS_SQS_URL = os.getenv("AWS_SQS_URL")
AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "eu-central-1")

def publish_to_queue(message: dict) -> bool:
    try:
        import boto3
        sqs = boto3.client('sqs', region_name=AWS_REGION)
        sqs.send_message(
            QueueUrl=AWS_SQS_URL,
            MessageBody=json.dumps(message)
        )
        logging.info(f"Messaggio inviato con successo a SQS per il job {message.get('job_id')}")
        return True
    except Exception as e:
        logging.error(f"Errore invio in coda SQS: {str(e)}")
        return False




@app.post("/api/v1/search")
def search(
    file: Optional[UploadFile] = File(None),
    test_image_id: Optional[str] = Form(None),
    graph_json: Optional[str] = Form(None),
    training_set: Optional[str] = Form("fullset"),
    architecture: Optional[str] = Form("semantic_web_gcn_gine_triplet"),
    vector_db_size: Optional[str] = Form("fullset"),
    use_cache: Optional[str] = Form("true")
    ):
    
    # Parsing manuale del booleano
    is_cache_enabled = str(use_cache).lower() in ["true", "1", "yes"]
    if file is None and test_image_id is None and graph_json is None:
        raise HTTPException(status_code=400, detail="Missing file, test_image_id or graph_json")
    
    job_id = str(uuid.uuid4())
    image_base64 = None
    unique_filename = None
    if file is not None:
        try:
            import base64
            # Use only job_id and extension to avoid spaces in SLURM args!
            ext = os.path.splitext(file.filename)[1]
            if not ext:
                ext = ".png"
            unique_filename = f"{job_id}{ext}"
            
            # Save locally for serving later (since exFAT mount is read-only)
            local_inference_dir = "/tmp/local_inference_images"
            os.makedirs(local_inference_dir, exist_ok=True)
            local_path = os.path.join(local_inference_dir, unique_filename)
            
            file.file.seek(0)
            file_bytes = file.file.read()
            with open(local_path, "wb") as f_out:
                f_out.write(file_bytes)
                
            image_base64 = base64.b64encode(file_bytes).decode('utf-8')
        except Exception as e:
            logging.error(f"Errore nella conversione/salvataggio dell'immagine: {str(e)}")
            raise HTTPException(status_code=500, detail="Failed to process uploaded file")

    # Controllo cache
    if is_cache_enabled and test_image_id is not None:
        r = get_redis_client()
        result_json = None
        
        if r:
            cache_val_key = f"cached_result:{training_set}:{architecture}:{vector_db_size}:{test_image_id}"
            result_json = r.get(cache_val_key)
            
        if not result_json:
            db = Session(engine)
            cached = db.query(CachedSearch).filter(
                CachedSearch.image_id == test_image_id,
                CachedSearch.training_set == training_set,
                CachedSearch.architecture == architecture,
                CachedSearch.vector_db_size == vector_db_size
            ).first()
            if cached:
                result_json = cached.result_json
                if r:
                    cache_val_key = f"cached_result:{training_set}:{architecture}:{vector_db_size}:{test_image_id}"
                    r.set(cache_val_key, result_json)
            db.close()
            
        if result_json:
            db = Session(engine)
            job = Job(job_id=job_id, status="COMPLETED", result=result_json)
            db.add(job)
            db.commit()
            db.close()
            
            r = get_redis_client()
            if r:
                r.hset(job_id, mapping={"status": "COMPLETED", "result": result_json})
                r.expire(job_id, 3600)
            
            return {"job_id": job_id, "status": "COMPLETED", "cached": True}

    # Se non c'è in cache, mettiamo in coda
    db = Session(engine)
    job = Job(job_id=job_id)
    db.add(job)
    db.commit()
    db.refresh(job)
    db.close()
    
    r = get_redis_client()
    if r is None:
        raise HTTPException(status_code=500, detail="Redis connection failed")
    
    job_cache: dict = {"job_id": job_id, "status": "PROCESSING"}
    r.hset(job_id, mapping=job_cache)
    r.expire(job_id, 3600)
    
    message = {
        "job_id": job_id,
        "file_path": None,
        "image_base64": image_base64,
        "filename": unique_filename,
        "test_image_id": test_image_id,
        "graph_json": graph_json,
        "training_set": training_set,
        "architecture": architecture,
        "vector_db_size": vector_db_size
    }
    success = publish_to_queue(message)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to queue job")
    
    return {"job_id": job_id, "status": "PROCESSING", "message": "Job created and sent to the queue"}

@app.get("/api/v1/status/{job_id}")
def get_status(job_id: str):
    #cerco su Redis
    r = get_redis_client()
    if r is None:
        raise HTTPException(status_code=500, detail="Redis connection failed")
    job = r.hgetall(job_id)

    if job:
        return {"job":job, "message": "Job found in Redis"}

    #Cerco su Postgres
    db = Session(engine)
    job = db.get(Job, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")

    #Aggiorno Redis con lo stato attuale preso da Postgres
    job_to_store : dict = {"job_id":job.job_id,"status":job.status,"result":job.result if job.result else ""}
    r.hset(job_id, mapping=job_to_store)
    r.expire(job_id, 3600)

    result = job.dict()
    db.close()
    
    return {"job":result, "message": "Job found in Postgres and save in Redis"}

@app.get("/api/v1/results/{job_id}")
def get_results(job_id: str):
    
    db = Session(engine)
    job = db.get(Job, job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.status != "COMPLETED":
        raise HTTPException(status_code=400, detail="Job not completed yet")
    
    result = job.result
    db.close()
    
    import json
    if result and isinstance(result, str):
        try:
            return json.loads(result)
        except json.JSONDecodeError:
            pass
    return result


if __name__ == "__main__":
    # pyrefly: ignore [missing-import]
    import uvicorn

    uvicorn.run("main:app",
    host="0.0.0.0",
    port=8000,
    reload=True)
