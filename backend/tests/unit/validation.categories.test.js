'use strict';

const Joi = require('joi');

const categoriesSchema = Joi.object({
  categories: Joi.array()
    .items(
      Joi.string().valid('classic', 'food', 'space', 'fantasy', 'tech')
    )
});

describe('BUG-001 — categories field validation', () => {

  test('null categories should fail validation (the bug)', () => {
    const { error } = categoriesSchema.validate({ categories: null });
    expect(error).toBeDefined();
    expect(error.details[0].message).toContain('"categories" must be an array');
  });

  test('empty array categories should pass validation (the fix)', () => {
    const { error } = categoriesSchema.validate({ categories: [] });
    expect(error).toBeUndefined();
  });

  test('valid category value should pass validation', () => {
    const { error } = categoriesSchema.validate({ categories: ['classic'] });
    expect(error).toBeUndefined();
  });

  test('invalid category value should fail validation', () => {
    const { error } = categoriesSchema.validate({ categories: ['invalid_value'] });
    expect(error).toBeDefined();
  });

});
