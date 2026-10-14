class_name BedSaveStore
extends RefCounted
## Один слот. .tmp/.bak — только транзакционные файлы, не игровые слоты.
## Не используем load() для файла игрока: JSON + версия + контрольная сумма.

const DEFAULT_PATH := "user://saves/bed_checkpoint.json"
const MAX_BYTES := 4 * 1024 * 1024
var slot_path: String = DEFAULT_PATH


func exists() -> bool:
	return FileAccess.file_exists(slot_path) or FileAccess.file_exists(slot_path + ".bak")


func read_slot() -> Dictionary:
	var main := _read(slot_path)
	if main.ok: return main
	var backup := _read(slot_path + ".bak")
	if backup.ok:
		backup["recovered"] = true
		return backup
	return main


func write_slot(data: Dictionary) -> Dictionary:
	var directory := ProjectSettings.globalize_path(slot_path.get_base_dir())
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK: return _fail("Не удалось создать папку сохранений.")
	var recovered := _recover_before_write()
	if not recovered.ok: return recovered
	var payload := JSON.stringify(data)
	var text := JSON.stringify({"format": "bed-checkpoint", "version": 1, "payload": payload, "sha256": payload.sha256_text()})
	if text.to_utf8_buffer().size() > MAX_BYTES: return _fail("Сохранение превышает допустимый размер.")
	var temp := slot_path + ".tmp"
	var backup := slot_path + ".bak"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return _fail("Не удалось записать временный файл сохранения.")
	file.store_string(text); file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return _fail("Ошибка записи: прежнее сохранение не заменено.")
	var verified := _read(temp)
	if not verified.ok: return _fail("Не удалось проверить записанный файл: прежнее сохранение не заменено.")
	var had_old := FileAccess.file_exists(slot_path)
	if had_old and _rename(slot_path, backup) != OK:
		return _fail("Не удалось защитить прежнее сохранение: замена отменена.")
	if _rename(temp, slot_path) != OK:
		if had_old: _rename(backup, slot_path)
		return _fail("Не удалось заменить сохранение. Прежняя запись сохранена.")
	if had_old: DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	return {"ok": true}


func _recover_before_write() -> Dictionary:
	var backup := slot_path + ".bak"
	if not FileAccess.file_exists(backup): return {"ok": true}
	if _read(slot_path).ok:
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(backup)) != OK:
			return _fail("Не удалось очистить незавершённую транзакцию сохранения.")
		return {"ok": true}
	if not _read(backup).ok: return _fail("Повреждены файлы предыдущей транзакции. Замена отменена.")
	if FileAccess.file_exists(slot_path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path)) != OK:
		return _fail("Не удалось восстановить прежнее сохранение.")
	if _rename(backup, slot_path) != OK: return _fail("Не удалось восстановить резервную запись.")
	return {"ok": true}


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return _fail("Сохранения после сна пока нет.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _fail("Не удалось открыть сохранение.")
	var length := file.get_length()
	if length <= 0 or length > MAX_BYTES:
		file.close(); return _fail("Некорректный размер файла сохранения.")
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK: return _fail("Файл сохранения повреждён (JSON).")
	var envelope: Variant = parser.data
	if not envelope is Dictionary or envelope.get("format") != "bed-checkpoint" or envelope.get("version") != 1:
		return _fail("Неизвестный формат сохранения.")
	if not envelope.get("payload") is String or not envelope.get("sha256") is String:
		return _fail("Повреждена структура сохранения.")
	var payload: String = envelope.payload
	if payload.sha256_text() != envelope.sha256: return _fail("Контрольная сумма сохранения не совпадает.")
	var body := JSON.new()
	if body.parse(payload) != OK or not body.data is Dictionary: return _fail("Повреждено состояние игры.")
	return {"ok": true, "data": body.data, "recovered": false}


func _rename(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
