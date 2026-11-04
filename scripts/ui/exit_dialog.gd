class_name ExitDialog
extends ConfirmationDialog
## Potvrzovací formulář ukončení hry. Použití: přidat jako dítě, tlačítko volá popup_centered().

func _init() -> void:
	title = "Ukončit hru"
	dialog_text = "Opravdu chceš ukončit hru?\nNeuložený postup se ztratí."
	ok_button_text = "Ano, ukončit"
	cancel_button_text = "Zpět do hry"
	confirmed.connect(func() -> void: Engine.get_main_loop().quit())
