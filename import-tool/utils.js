
import R from "ramda";

const trimmedProp = R.compose(R.trim, String, R.or(R.__, ""), R.prop);

export const getCellValue = R.compose(
    R.either(trimmedProp("customValue"), trimmedProp("originalValue")),
    R.or(R.__, {})
);

export const didPressEnter = R.compose(R.equals("Enter"), R.prop("key"));
