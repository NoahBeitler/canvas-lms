/*
 * Copyright (C) 2021 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import {gql} from '@apollo/client'
import {bool, shape, string} from 'prop-types'

export const Course = {
  fragment: gql`
    fragment Course on Course {
      _id
      courseNickname
      contextName: name
      assetString
      horizonCourse
    }
  `,

  shape: shape({
    _id: string,
    courseNickname: string,
    contextName: string,
    assetString: string,
    horizonCourse: bool,
  }),

  mock: ({
    _id = '195',
    courseNickname = 'Ipsum',
    contextName = 'XavierSchool',
    assetString = 'course_195',
    horizonCourse = false,
  } = {}) => ({
    _id,
    courseNickname,
    contextName,
    assetString,
    horizonCourse,
    __typename: 'Course',
  }),
}
