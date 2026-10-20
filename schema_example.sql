DROP TABLE IF EXISTS drugs;
DROP TABLE IF EXISTS generics;

CREATE TABLE generics (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE drugs (
    id           INTEGER PRIMARY KEY,
    brand_name   TEXT NOT NULL UNIQUE,
    generic_id   INTEGER NOT NULL REFERENCES generics(id),
    image_path   TEXT,
    indications  TEXT,
    source_row   INTEGER
);

CREATE INDEX idx_drugs_brand   ON drugs(brand_name);
CREATE INDEX idx_generics_name ON generics(name);
