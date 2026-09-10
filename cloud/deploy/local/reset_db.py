from backend.main import engine, TestImage, Session, SQLModel, init_db
print("Dropping tables...")
SQLModel.metadata.drop_all(engine)
print("Creating tables...")
SQLModel.metadata.create_all(engine)
print("Running init_db...")
init_db()
print("Done.")
