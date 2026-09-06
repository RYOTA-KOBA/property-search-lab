class PropertyImage < ApplicationRecord
  include EmitsCdcEvent

  belongs_to :property
end
