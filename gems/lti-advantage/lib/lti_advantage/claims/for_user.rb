# frozen_string_literal: true

#
# Copyright (C) 2025 - present Instructure, Inc.
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

require "active_model"

module LtiAdvantage::Claims
  # Class represeting an LTI 1.3 message for_user claim.
  # https://purl.imsglobal.org/spec/lti/claim/for_user
  class ForUser
    include ActiveModel::Model

    attr_accessor :user_id,
                  :person_sourcedid,
                  :given_name,
                  :family_name,
                  :name,
                  :email,
                  :roles

    validates_presence_of :user_id
  end
end
