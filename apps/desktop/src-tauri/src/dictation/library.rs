use std::{
    fs::{self, File, OpenOptions},
    io::{ErrorKind, Write},
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};

use super::engine::{Result, SpeechOptions};

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub id: u64,
    pub created_at: u64,
    pub text: String,
    #[serde(default)]
    pub pinned: bool,
    #[serde(default)]
    pub archived: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Library {
    pub options: SpeechOptions,
    pub entries: Vec<Entry>,
    pub shortcuts: bool,
    pub speech_model: String,
    next_id: u64,
}

impl Default for Library {
    fn default() -> Self {
        Self {
            options: Default::default(),
            entries: Vec::new(),
            shortcuts: false,
            speech_model: super::catalog::DEFAULT_ID.into(),
            next_id: 0,
        }
    }
}

fn read(dir: &Path) -> Result<Library> {
    match File::open(dir.join("dictation-v1.json")) {
        Ok(file) => serde_json::from_reader(file).map_err(
            |_| "The local library could not be read. Your existing file has been preserved.",
        ),
        Err(err) if err.kind() == ErrorKind::NotFound => Ok(Library::default()),
        Err(_) => Err("The local library could not be opened."),
    }
}

pub fn load(dir: &Path) -> Result<Library> {
    read(dir)
}

pub fn update<T>(dir: &Path, change: impl FnOnce(&mut Library) -> Result<T>) -> Result<T> {
    fs::create_dir_all(dir).map_err(|_| "The local library folder is unavailable.")?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(dir.join("dictation.lock"))
        .map_err(|_| "The local library is unavailable.")?;
    fs2::FileExt::lock_exclusive(&lock).map_err(|_| "The local library is busy.")?;
    let mut library = read(dir)?;
    let result = change(&mut library)?;
    let mut tmp = tempfile::NamedTempFile::new_in(dir)
        .map_err(|_| "The local library could not be saved.")?;
    serde_json::to_writer(&mut tmp, &library)
        .map_err(|_| "The local library could not be saved.")?;
    tmp.flush()
        .and_then(|_| tmp.as_file().sync_all())
        .map_err(|_| "The local library could not be saved.")?;
    tmp.persist(dir.join("dictation-v1.json"))
        .map_err(|_| "The local library could not be saved.")?;
    Ok(result)
}

impl Library {
    pub fn save(&mut self, id: Option<u64>, text: String) -> Result<u64> {
        if text.trim().is_empty() {
            return Err("Enter some text first.");
        }
        if let Some(id) = id {
            let entry = self
                .entries
                .iter_mut()
                .find(|n| n.id == id)
                .ok_or("This transcript was deleted.")?;
            entry.text = text;
            return Ok(id);
        }
        self.next_id = self
            .next_id
            .checked_add(1)
            .ok_or("A transcript ID could not be assigned.")?;
        let created_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        self.entries.insert(
            0,
            Entry {
                id: self.next_id,
                created_at,
                text,
                pinned: false,
                archived: false,
            },
        );
        Ok(self.next_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn explicit_save_edit_delete_and_failed_writes_preserve_existing_data() {
        let path = tempfile::tempdir().unwrap();
        assert!(load(path.path()).unwrap().entries.is_empty());
        let id = update(path.path(), |db| db.save(None, "First".into())).unwrap();
        update(path.path(), |db| db.save(Some(id), "Edited".into())).unwrap();
        assert!(update(path.path(), |db| db.save(Some(987), "Missing".into())).is_err());
        assert_eq!(load(path.path()).unwrap().entries[0].text, "Edited");
        update(path.path(), |db| {
            db.entries.retain(|e| e.id != id);
            Ok(())
        })
        .unwrap();
        assert!(load(path.path()).unwrap().entries.is_empty());
        fs::write(path.path().join("dictation-v1.json"), "broken").unwrap();
        assert!(update(path.path(), |db| db.save(None, "do not overwrite".into())).is_err());
        assert_eq!(
            fs::read_to_string(path.path().join("dictation-v1.json")).unwrap(),
            "broken"
        );
    }
}
