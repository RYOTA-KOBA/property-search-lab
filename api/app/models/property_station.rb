class PropertyStation < ApplicationRecord
  include EmitsCdcEvent

  belongs_to :property
end
