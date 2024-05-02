defprotocol Y.Type do
  def highest_clock(type, client \\ nil)
  def highest_clock_with_length(type, client \\ nil)
  def highest_clock_by_client_id(type)
  def highest_clock_with_length_by_client_id(type)
  def pack(type)
  def to_list(type, opts \\ [])
  def find(type, id, default \\ nil)
  def unsafe_replace(type, item, with_items)
  def between(type, left, right)
  def add_after(type, after_item, item)
  def add_before(type, before_item, item)
  def next(type, item)
  def prev(type, item)
  def first(type, reference_item)
  def last(type, reference_item)
  def delete(type, transaction, id)
  def type_ref(type)
end

# export const YArrayRefID = 0
# export const YMapRefID = 1
# export const YTextRefID = 2
# export const YXmlElementRefID = 3
# export const YXmlFragmentRefID = 4
# export const YXmlHookRefID = 5
# export const YXmlTextRefID = 6
#
