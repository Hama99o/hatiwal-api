class ApplicationSerializer < Blueprinter::Base
  def self.model_name
    ActiveModel::Name.new(self, nil, name.delete_suffix("Serializer"))
  end
end
