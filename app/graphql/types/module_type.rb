# frozen_string_literal: true

#
# Copyright (C) 2018 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

class ModuleItemsVisibleLoader < GraphQL::Batch::Loader
  def initialize(user)
    super()
    @user = user
  end

  def perform(context_modules)
    GuardRail.activate(:secondary) do
      ActiveRecord::Associations.preload(context_modules, content_tags: { content: :context })
      context_modules.each do |context_module|
        content_tags = context_module.content_tags_visible_to(@user)
        fulfill(context_module, content_tags)
      end
    end
  end
end

module Types
  class ModuleType < ApplicationObjectType
    graphql_name "Module"

    implements GraphQL::Types::Relay::Node
    implements Interfaces::TimestampInterface
    implements Interfaces::LegacyIDInterface

    class ModulePrerequisiteType < ApplicationObjectType
      field :id, ID, null: false
      field :name, String, null: false
      field :type, String, null: false
    end

    class ModuleCompletionRequirementType < ApplicationObjectType
      field :id, ID, null: false
      field :min_percentage, Float, null: true
      field :min_score, Float, null: true
      field :type, String, null: false
    end

    alias_method :context_module, :object

    global_id_field :id

    field :name, String, null: true

    field :unlock_at, DateTimeType, null: true

    field :position, Integer, null: true

    field :prerequisites, [ModulePrerequisiteType], null: true
    delegate :prerequisites, to: :context_module

    field :completion_requirements, [ModuleCompletionRequirementType], null: true
    delegate :completion_requirements, to: :context_module

    field :requirement_count, Integer, null: true
    delegate :requirement_count, to: :context_module

    field :published, Boolean, null: true, method: :published?

    field :module_items, [Types::ModuleItemType], null: true
    def module_items
      ModuleItemsVisibleLoader.for(current_user).load(context_module)
    end

    field :estimated_duration, GraphQL::Types::ISO8601Duration, null: true
    def estimated_duration
      module_items.then do |content_tags|
        return nil if content_tags.all?(&:estimated_duration).nil?

        content_tags.sum { |item| item.estimated_duration&.duration || 0 }.iso8601
      end
    end
  end
end
