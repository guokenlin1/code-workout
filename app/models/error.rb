# == Schema Information
#
# Table name: errors
#
#  id          :integer          not null, primary key
#  usable_type :string(255)
#  usable_id   :integer
#  class_name  :text
#  message     :text
#  trace       :text
#  target_url  :text
#  referer_url :text
#  params      :text
#  user_agent  :text
#  created_at  :datetime
#  updated_at  :datetime
#
# Indexes
#
#  index_errors_on_class_name  (class_name)
#  index_errors_on_created_at  (created_at)
#

class Error < ActiveRecord::Base
#  belongs_to :usable, polymorphic: true
end