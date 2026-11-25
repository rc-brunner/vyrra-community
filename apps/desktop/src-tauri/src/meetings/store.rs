use super::{Plan, Profile, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs::{self, File, OpenOptions},
    io::{ErrorKind, Write},
    path::Path,
};
#[derive(Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Store {
    pub profile: Profile,
    pub plans: Vec<Plan>,
}
pub fn read(dir: &Path) -> Result<Store> {
    match File::open(dir.join("meetings-v1.json")) {
        Ok(file) => serde_json::from_reader(file)
            .map_err(|_| "The meeting file is unreadable. The existing file was preserved."),
        Err(err) if err.kind() == ErrorKind::NotFound => Ok(Store::default()),
        Err(_) => Err("Your meeting file is unavailable."),
    }
}
pub fn update<T>(dir: &Path, f: impl FnOnce(&mut Store) -> Result<T>) -> Result<T> {
    fs::create_dir_all(dir).map_err(|_| "The meeting folder is unavailable.")?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(dir.join("meetings.lock"))
        .map_err(|_| "The meeting folder is unavailable.")?;
    fs2::FileExt::lock_exclusive(&lock).map_err(|_| "The meeting file is busy.")?;
    let mut data = read(dir)?;
    let result = f(&mut data)?;
    let error = |_| "The meeting could not be saved.";
    let mut tmp = tempfile::NamedTempFile::new_in(dir).map_err(error)?;
    serde_json::to_writer(&mut tmp, &data).map_err(|_| "The meeting could not be saved.")?;
    tmp.flush()
        .and_then(|_| tmp.as_file().sync_all())
        .map_err(error)?;
    tmp.persist(dir.join("meetings-v1.json"))
        .map_err(|_| "The meeting could not be saved.")?;
    Ok(result)
}

pub fn owner(dir: &Path) -> Result<File> {
    fs::create_dir_all(dir).map_err(|_| "Meeting folder unavailable.")?;
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(dir.join("meetings-owner.lock"))
        .map_err(|_| "Meeting scheduler unavailable.")?;
    fs2::FileExt::try_lock_exclusive(&f)
        .map_err(|_| "The scheduler is running in another window.")?;
    Ok(f)
}
