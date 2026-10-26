from rambu.mask import MASK, mask_sensitive


def test_masks_digit_codes():
    assert mask_sensitive("The code is 482913.") == f"The code is {MASK}."
    assert mask_sensitive("It's 482 913") == f"It's {MASK}"
    assert mask_sensitive("PIN 1-2-3-4") == f"PIN {MASK}"


def test_masks_spelled_out_digits_in_both_languages():
    assert mask_sensitive("four eight two nine one three") == MASK
    assert mask_sensitive("kodenya satu dua tiga empat") == f"kodenya {MASK}"


def test_keeps_money_and_short_numbers():
    assert mask_sensitive("a transfer of 8,000,000 rupiah") == "a transfer of 8,000,000 rupiah"
    assert mask_sensitive("Rp 8.000.000 sudah masuk") == "Rp 8.000.000 sudah masuk"
    assert mask_sensitive("a six-digit code at 10 am") == "a six-digit code at 10 am"
    assert mask_sensitive("eight million rupiah") == "eight million rupiah"
