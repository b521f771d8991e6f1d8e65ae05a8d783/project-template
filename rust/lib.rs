use wasm_bindgen::prelude::wasm_bindgen;

#[wasm_bindgen]
pub fn get_1() -> i32 {
    return 1;
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn test_get_1() {
        assert!(get_1() == 1);
    }
}
